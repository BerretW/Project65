#!/usr/bin/env python3
"""
P65 SBC Uploader
----------------
GUI nástroj pro nahrávání programů do P65 BigBoard.

Podporuje dva režimy připojení:
  - COM port  – reálný hardware (ACIA R6551, 19200 Bd, 8N1)
  - TCP       – emulátor p65emu (výchozí 127.0.0.1:6551)

Protokol bootloaderu:
  w  – nahrání raw binary (přesně 8192 B → $6000–$7FFF)
  h  – nahrání Intel HEX (libovolná adresa)
  s  – skok na $6000
  m  – EWOZ / WozMon monitor
  ^R – soft restart bootloaderu

Závislosti: pip install pyserial
"""

import tkinter as tk
from tkinter import ttk, filedialog, scrolledtext, messagebox
import serial
import serial.tools.list_ports
import threading
import socket
import os
import time
import queue

BAUD_RATE   = 19200
UPLOAD_SIZE = 8192
CHUNK_SIZE  = 128

DEFAULT_TCP_HOST = "127.0.0.1"
DEFAULT_TCP_PORT = "6551"


# ---------------------------------------------------------------------------
# Abstrakce připojení — jednotné rozhraní pro COM i TCP
# ---------------------------------------------------------------------------

class SerialConn:
    """Wrapper kolem pyserial."""
    def __init__(self, port: str, baud: int):
        self._ser = serial.Serial(
            port, baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.05,
        )

    @property
    def is_open(self) -> bool:
        return self._ser and self._ser.is_open

    def write(self, data: bytes):
        self._ser.write(data)

    def read(self, n: int) -> bytes:
        return self._ser.read(n)

    def close(self):
        try:
            self._ser.close()
        except Exception:
            pass

    def description(self) -> str:
        return f"{self._ser.port}  {self._ser.baudrate} Bd 8N1"


class TcpConn:
    """TCP socket – pro p65emu nebo com2tcp bridge."""
    def __init__(self, host: str, port: int):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.connect((host, port))
        self._sock.setblocking(False)
        self._host = host
        self._port = port
        self._open = True

    @property
    def is_open(self) -> bool:
        return self._open

    def write(self, data: bytes):
        self._sock.sendall(data)

    def read(self, n: int) -> bytes:
        try:
            return self._sock.recv(n)
        except BlockingIOError:
            return b""
        except OSError:
            self._open = False
            return b""

    def close(self):
        self._open = False
        try:
            self._sock.close()
        except Exception:
            pass

    def description(self) -> str:
        return f"TCP  {self._host}:{self._port}"


# ---------------------------------------------------------------------------
class P65Uploader:
    def __init__(self, root: tk.Tk):
        self.root  = root
        self.conn  = None          # SerialConn nebo TcpConn
        self.running = False
        self.rx_queue: queue.Queue = queue.Queue()
        self._upload_in_progress = False
        self._upload_total = UPLOAD_SIZE

        root.title("P65 SBC Uploader")
        root.resizable(False, False)
        root.protocol("WM_DELETE_WINDOW", self._on_close)

        self._build_ui()
        self._refresh_ports()
        self._poll_rx()

    # -----------------------------------------------------------------------
    # UI
    # -----------------------------------------------------------------------
    def _build_ui(self):
        PAD = dict(padx=6, pady=4)

        # ── Připojení ───────────────────────────────────────────────────────
        frm_conn = ttk.LabelFrame(self.root, text="Připojení")
        frm_conn.grid(row=0, column=0, columnspan=2, sticky="ew", **PAD)

        # Volba režimu
        self.mode_var = tk.StringVar(value="com")
        ttk.Radiobutton(frm_conn, text="COM port", variable=self.mode_var,
                        value="com", command=self._on_mode_change
                        ).grid(row=0, column=0, padx=(6, 2), pady=4)
        ttk.Radiobutton(frm_conn, text="TCP (emulátor)", variable=self.mode_var,
                        value="tcp", command=self._on_mode_change
                        ).grid(row=0, column=1, padx=(2, 6), pady=4)

        # COM pole
        self.frm_com = ttk.Frame(frm_conn)
        self.frm_com.grid(row=1, column=0, columnspan=2, sticky="ew")

        ttk.Label(self.frm_com, text="Port:").grid(row=0, column=0, **PAD)
        self.port_var = tk.StringVar()
        self.port_cb  = ttk.Combobox(self.frm_com, textvariable=self.port_var,
                                     width=16, state="readonly")
        self.port_cb.grid(row=0, column=1, **PAD)
        self.btn_refresh = ttk.Button(self.frm_com, text="↺", width=3,
                                      command=self._refresh_ports)
        self.btn_refresh.grid(row=0, column=2, **PAD)
        ttk.Label(self.frm_com, text=f"{BAUD_RATE} Bd 8N1",
                  foreground="gray").grid(row=0, column=3, **PAD)

        # TCP pole
        self.frm_tcp = ttk.Frame(frm_conn)
        self.frm_tcp.grid(row=1, column=0, columnspan=2, sticky="ew")
        self.frm_tcp.grid_remove()   # skryto při startu

        ttk.Label(self.frm_tcp, text="Host:").grid(row=0, column=0, **PAD)
        self.tcp_host_var = tk.StringVar(value=DEFAULT_TCP_HOST)
        ttk.Entry(self.frm_tcp, textvariable=self.tcp_host_var,
                  width=16).grid(row=0, column=1, **PAD)
        ttk.Label(self.frm_tcp, text="Port:").grid(row=0, column=2, **PAD)
        self.tcp_port_var = tk.StringVar(value=DEFAULT_TCP_PORT)
        ttk.Entry(self.frm_tcp, textvariable=self.tcp_port_var,
                  width=7).grid(row=0, column=3, **PAD)

        # Připojit / Odpojit + status
        frm_btns = ttk.Frame(frm_conn)
        frm_btns.grid(row=2, column=0, columnspan=2, sticky="ew")

        self.btn_connect = ttk.Button(frm_btns, text="Připojit",
                                      command=self._toggle_connect)
        self.btn_connect.grid(row=0, column=0, **PAD)
        self.lbl_status = ttk.Label(frm_btns, text="●  Odpojeno",
                                    foreground="gray")
        self.lbl_status.grid(row=0, column=1, padx=10)

        # ── Nahrání souboru ─────────────────────────────────────────────────
        frm_file = ttk.LabelFrame(self.root, text="Nahrání programu")
        frm_file.grid(row=1, column=0, columnspan=2, sticky="ew", **PAD)

        self.file_var = tk.StringVar()
        ttk.Entry(frm_file, textvariable=self.file_var, width=46,
                  state="readonly").grid(row=0, column=0, **PAD)
        ttk.Button(frm_file, text="Vybrat soubor…",
                   command=self._pick_file).grid(row=0, column=1, **PAD)
        self.btn_upload = ttk.Button(frm_file, text="⬆  Nahrát",
                                     command=self._upload, state="disabled")
        self.btn_upload.grid(row=0, column=2, **PAD)

        self.progress = ttk.Progressbar(frm_file, length=350,
                                        maximum=UPLOAD_SIZE, mode="determinate")
        self.progress.grid(row=1, column=0, columnspan=2, sticky="ew",
                           padx=6, pady=(0, 4))
        self.lbl_progress = ttk.Label(frm_file, text="")
        self.lbl_progress.grid(row=1, column=2, **PAD)

        # ── Rychlé příkazy ──────────────────────────────────────────────────
        frm_cmd = ttk.LabelFrame(self.root, text="Příkazy")
        frm_cmd.grid(row=2, column=0, columnspan=2, sticky="ew", **PAD)

        cmds = [
            ("▶  Start ($6000)", self._cmd_start,   "green"),
            ("M  WozMon",        self._cmd_monitor,  None),
            ("^R Restart",       self._cmd_reset,    "red"),
        ]
        for col, (label, cmd, fg) in enumerate(cmds):
            btn = ttk.Button(frm_cmd, text=label, command=cmd, width=18)
            btn.grid(row=0, column=col, **PAD)
            if fg:
                btn.configure(style=f"{fg}.TButton")

        # ── Terminál ────────────────────────────────────────────────────────
        frm_term = ttk.LabelFrame(self.root, text="Terminál")
        frm_term.grid(row=3, column=0, columnspan=2, sticky="nsew", **PAD)

        self.txt_term = scrolledtext.ScrolledText(
            frm_term, width=62, height=18,
            bg="#1e1e1e", fg="#d4d4d4",
            insertbackground="white",
            font=("Consolas", 10),
            state="disabled",
        )
        self.txt_term.grid(row=0, column=0, columnspan=3, **PAD)
        self.txt_term.tag_config("tx",    foreground="#569cd6")
        self.txt_term.tag_config("info",  foreground="#6a9955")
        self.txt_term.tag_config("error", foreground="#f44747")
        self.txt_term.tag_config("prog",  foreground="#ce9178")

        self.input_var = tk.StringVar()
        ent_input = ttk.Entry(frm_term, textvariable=self.input_var, width=50)
        ent_input.grid(row=1, column=0, padx=6, pady=(0, 4), sticky="ew")
        ent_input.bind("<Return>", self._send_line)
        ttk.Button(frm_term, text="Odeslat",
                   command=self._send_line).grid(row=1, column=1, padx=(0, 4))
        ttk.Button(frm_term, text="Vymazat",
                   command=self._clear_term).grid(row=1, column=2, padx=(0, 4))

        style = ttk.Style()
        style.configure("green.TButton", foreground="darkgreen")
        style.configure("red.TButton",   foreground="darkred")

    # -----------------------------------------------------------------------
    def _on_mode_change(self):
        if self.conn:
            self._disconnect()
        if self.mode_var.get() == "tcp":
            self.frm_com.grid_remove()
            self.frm_tcp.grid()
        else:
            self.frm_tcp.grid_remove()
            self.frm_com.grid()

    # -----------------------------------------------------------------------
    # Porty
    # -----------------------------------------------------------------------
    def _refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.port_cb["values"] = ports
        if ports and not self.port_var.get():
            self.port_var.set(ports[0])

    # -----------------------------------------------------------------------
    # Připojení
    # -----------------------------------------------------------------------
    def _toggle_connect(self):
        if self.conn and self.conn.is_open:
            self._disconnect()
        else:
            self._connect()

    def _connect(self):
        try:
            if self.mode_var.get() == "tcp":
                host = self.tcp_host_var.get().strip() or DEFAULT_TCP_HOST
                port = int(self.tcp_port_var.get().strip() or DEFAULT_TCP_PORT)
                self.conn = TcpConn(host, port)
            else:
                com = self.port_var.get()
                if not com:
                    messagebox.showerror("Chyba", "Vyber COM port.")
                    return
                self.conn = SerialConn(com, BAUD_RATE)

            self.running = True
            threading.Thread(target=self._read_loop, daemon=True).start()

            desc = self.conn.description()
            self.lbl_status.config(text=f"●  {desc}", foreground="green")
            self.btn_connect.config(text="Odpojit")
            self.btn_upload.config(state="normal")
            self._log(f"Připojeno: {desc}\n", "info")

        except (serial.SerialException, OSError, ValueError) as e:
            messagebox.showerror("Chyba připojení", str(e))
            self.conn = None

    def _disconnect(self):
        self.running = False
        if self.conn:
            self.conn.close()
            self.conn = None
        self.lbl_status.config(text="●  Odpojeno", foreground="gray")
        self.btn_connect.config(text="Připojit")
        self.btn_upload.config(state="disabled")
        self._log("Odpojeno.\n", "info")

    # -----------------------------------------------------------------------
    # Čtení (vlákno)
    # -----------------------------------------------------------------------
    def _read_loop(self):
        while self.running and self.conn and self.conn.is_open:
            data = self.conn.read(64)
            if data:
                self.rx_queue.put(data)
            else:
                time.sleep(0.01)
        # Pokud se TCP odpojilo ze strany serveru, informuj UI
        if self.running:
            self.running = False
            self.root.after(0, self._on_remote_disconnect)

    def _on_remote_disconnect(self):
        if self.conn:
            self.conn.close()
            self.conn = None
        self.lbl_status.config(text="●  Odpojeno", foreground="gray")
        self.btn_connect.config(text="Připojit")
        self.btn_upload.config(state="disabled")
        self._log("Spojení ukončeno vzdálenou stranou.\n", "error")

    def _poll_rx(self):
        try:
            while True:
                data = self.rx_queue.get_nowait()
                text = data.decode("ascii", errors="replace")
                self._append_term(text)
        except queue.Empty:
            pass
        finally:
            self.root.after(50, self._poll_rx)

    # -----------------------------------------------------------------------
    # Terminál
    # -----------------------------------------------------------------------
    def _log(self, msg: str, tag: str = "info"):
        self.txt_term.config(state="normal")
        self.txt_term.insert(tk.END, msg, tag)
        self.txt_term.see(tk.END)
        self.txt_term.config(state="disabled")

    def _append_term(self, text: str, tag: str = ""):
        self.txt_term.config(state="normal")
        self.txt_term.insert(tk.END, text, tag)
        self.txt_term.see(tk.END)
        self.txt_term.config(state="disabled")

    def _clear_term(self):
        self.txt_term.config(state="normal")
        self.txt_term.delete("1.0", tk.END)
        self.txt_term.config(state="disabled")

    # -----------------------------------------------------------------------
    # Vstup
    # -----------------------------------------------------------------------
    def _send_line(self, event=None):
        if not self._is_connected():
            return
        text = self.input_var.get()
        self.input_var.set("")
        if text:
            self.conn.write((text + "\r").encode("ascii", errors="replace"))
            self._log(text + "\n", "tx")

    def _send_byte(self, b: bytes):
        if self._is_connected():
            self.conn.write(b)

    # -----------------------------------------------------------------------
    # Příkazy bootloaderu
    # -----------------------------------------------------------------------
    def _cmd_start(self):
        if not self._is_connected(): return
        self._send_byte(b"s")
        self._log("→ s  (spuštění z $6000)\n", "tx")

    def _cmd_monitor(self):
        if not self._is_connected(): return
        self._send_byte(b"m")
        self._log("→ m  (EWOZ / WozMon)\n", "tx")

    def _cmd_reset(self):
        if not self._is_connected(): return
        self._send_byte(b"\x12")
        self._log("→ ^R (soft restart)\n", "tx")

    # -----------------------------------------------------------------------
    # Výběr souboru
    # -----------------------------------------------------------------------
    def _pick_file(self):
        path = filedialog.askopenfilename(
            title="Vyber soubor programu",
            filetypes=[
                ("Programy P65",    "*.bin *.hex"),
                ("Binární soubory", "*.bin"),
                ("Intel HEX",       "*.hex"),
                ("Všechny soubory", "*.*"),
            ],
            initialdir=os.path.join(os.path.dirname(__file__), "..",
                                    "Firmware", "ramtest", "output"),
        )
        if not path:
            return

        self.file_var.set(path)
        ext  = os.path.splitext(path)[1].lower()
        size = os.path.getsize(path)

        if ext == ".hex":
            try:
                with open(path) as f:
                    lines = [l.strip() for l in f if l.strip().startswith(":")]
                rec_count = sum(
                    1 for l in lines if not l.upper().startswith(":00000001")
                )
                self._log(
                    f"Soubor: {os.path.basename(path)}"
                    f"  ({rec_count} záznamů IHex, {size} B)\n", "info"
                )
            except Exception:
                self._log(f"Soubor: {os.path.basename(path)}  ({size} B)\n", "info")
            self.btn_upload.config(text="⬆  Nahrát (h) ihex")
        else:
            ok = size == UPLOAD_SIZE
            self._log(
                f"Soubor: {os.path.basename(path)}  ({size} B"
                + ("" if ok else f"  ≠ {UPLOAD_SIZE} B !")
                + ")\n",
                "info" if ok else "error",
            )
            self.btn_upload.config(text="⬆  Nahrát (w) bin")

    # -----------------------------------------------------------------------
    # Nahrání
    # -----------------------------------------------------------------------
    def _upload(self):
        if self._upload_in_progress or not self._is_connected():
            return
        path = self.file_var.get()
        if not path or not os.path.exists(path):
            messagebox.showerror("Chyba", "Nejprve vyber soubor (.bin nebo .hex)")
            return
        ext = os.path.splitext(path)[1].lower()
        if ext == ".hex":
            threading.Thread(target=self._do_upload_hex, args=(path,),
                             daemon=True).start()
        else:
            size = os.path.getsize(path)
            if size != UPLOAD_SIZE:
                messagebox.showerror(
                    "Špatná velikost",
                    f"Soubor .bin musí mít přesně {UPLOAD_SIZE} B.\n"
                    f"Tento soubor má {size} B.",
                )
                return
            threading.Thread(target=self._do_upload_bin, args=(path,),
                             daemon=True).start()

    # -----------------------------------------------------------------------
    # Raw binary (příkaz 'w')
    # -----------------------------------------------------------------------
    def _do_upload_bin(self, path: str):
        self._upload_in_progress = True
        self._upload_total = UPLOAD_SIZE
        self.root.after(0, self.btn_upload.config, {"state": "disabled"})
        self.root.after(0, self.progress.config,
                        {"maximum": UPLOAD_SIZE, "value": 0})
        try:
            with open(path, "rb") as f:
                data = f.read()

            self.conn.write(b"w")
            self.root.after(0, self._log, "→ w  (čekám na bootloader…)\n", "tx")
            time.sleep(0.3)

            sent = 0
            for i in range(0, len(data), CHUNK_SIZE):
                if not (self.conn and self.conn.is_open):
                    self.root.after(0, self._log,
                                    "Přenos přerušen – spojení ztraceno.\n", "error")
                    return
                chunk = data[i:i + CHUNK_SIZE]
                self.conn.write(chunk)
                sent += len(chunk)
                self.root.after(0, self._update_progress,
                                sent, sent * 100 // UPLOAD_SIZE)

            self.root.after(0, self._log,
                            f"Nahrání dokončeno ({sent} B).\n", "info")
            self.root.after(0, self.progress.config, {"value": UPLOAD_SIZE})
            self.root.after(0, self.lbl_progress.config, {"text": "100 %"})
        except Exception as e:
            self.root.after(0, self._log, f"Chyba při nahrávání: {e}\n", "error")
        finally:
            self._upload_in_progress = False
            self.root.after(0, self.btn_upload.config, {"state": "normal"})

    # -----------------------------------------------------------------------
    # Intel HEX (příkaz 'h')
    # -----------------------------------------------------------------------
    def _do_upload_hex(self, path: str):
        self._upload_in_progress = True
        self.root.after(0, self.btn_upload.config, {"state": "disabled"})
        try:
            with open(path) as f:
                raw_lines = f.readlines()

            records = [l.strip() for l in raw_lines if l.strip().startswith(":")]
            if not records:
                self.root.after(0, self._log,
                                "Prázdný nebo neplatný .hex soubor.\n", "error")
                return

            data_recs = sum(
                1 for r in records if not r.upper().startswith(":00000001")
            )
            payload = b"".join((r + "\r\n").encode("ascii") for r in records)
            total   = len(payload)
            self._upload_total = total

            self.root.after(0, self.progress.config,
                            {"maximum": total, "value": 0})
            self.root.after(
                0, self._log,
                f"→ h  (Intel HEX, {data_recs} záznamů, {total} B)\n", "tx",
            )

            self.conn.write(b"h")
            time.sleep(0.2)

            sent = 0
            for i in range(0, len(payload), CHUNK_SIZE):
                if not (self.conn and self.conn.is_open):
                    self.root.after(0, self._log,
                                    "Přenos přerušen – spojení ztraceno.\n", "error")
                    return
                chunk = payload[i:i + CHUNK_SIZE]
                self.conn.write(chunk)
                sent += len(chunk)
                self.root.after(0, self._update_progress,
                                sent, sent * 100 // total)

            self.root.after(
                0, self._log,
                f"Přenos HEX dokončen ({data_recs} záznamů). "
                f"Čekám na odpověď firmwaru…\n", "info",
            )
            self.root.after(0, self.progress.config, {"value": total})
            self.root.after(0, self.lbl_progress.config, {"text": "100 %"})
        except Exception as e:
            self.root.after(0, self._log,
                            f"Chyba při nahrávání HEX: {e}\n", "error")
        finally:
            self._upload_in_progress = False
            self.root.after(0, self.btn_upload.config, {"state": "normal"})
            self.root.after(0, self.progress.config,
                            {"maximum": UPLOAD_SIZE, "value": 0})
            self.root.after(0, self.lbl_progress.config, {"text": ""})

    # -----------------------------------------------------------------------
    def _update_progress(self, sent: int, pct: int):
        self.progress.config(value=sent)
        self.lbl_progress.config(text=f"{pct} %")
        if pct % 10 == 0:
            self._log(f"  … {sent}/{self._upload_total} B  ({pct} %)\n", "prog")

    def _is_connected(self) -> bool:
        if self.conn and self.conn.is_open:
            return True
        messagebox.showwarning("Nepřipojeno", "Nejprve se připoj.")
        return False

    def _on_close(self):
        self._disconnect()
        self.root.destroy()


# ---------------------------------------------------------------------------
def main():
    root = tk.Tk()
    app = P65Uploader(root)
    root.mainloop()


if __name__ == "__main__":
    main()
