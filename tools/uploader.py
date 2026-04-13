#!/usr/bin/env python3
"""
P65 SBC Uploader
----------------
GUI nástroj pro nahrávání binárních programů do P65 BigBoard
přes sériový port (ACIA R6551, 19200 Bd, 8N1).

Protokol bootloaderu:
  w  – nahrání raw binary (přesně 8192 B → $6000–$7FFF), po nahrání auto-start
  s  – skok na $6000 (spuštění naposledy nahraného programu)
  m  – EWOZ / WozMon monitor
  ^R – soft restart bootloaderu

Závislosti: pip install pyserial
"""

import tkinter as tk
from tkinter import ttk, filedialog, scrolledtext, messagebox
import serial
import serial.tools.list_ports
import threading
import os
import time
import queue

BAUD_RATE   = 19200
UPLOAD_SIZE = 8192      # bootloader čeká přesně 8192 B
CHUNK_SIZE  = 128       # bajtů na jeden zápis do portu


# ---------------------------------------------------------------------------
class P65Uploader:
    def __init__(self, root: tk.Tk):
        self.root  = root
        self.ser   = None
        self.running = False
        self.rx_queue: queue.Queue = queue.Queue()
        self._upload_in_progress = False

        root.title("P65 SBC Uploader")
        root.resizable(False, False)
        root.protocol("WM_DELETE_WINDOW", self._on_close)

        self._build_ui()
        self._refresh_ports()
        self._poll_rx()         # pravidelné čtení z fronty do terminálu

    # -----------------------------------------------------------------------
    # UI
    # -----------------------------------------------------------------------
    def _build_ui(self):
        PAD = dict(padx=6, pady=4)

        # ── Připojení ───────────────────────────────────────────────────────
        frm_conn = ttk.LabelFrame(self.root, text="Připojení")
        frm_conn.grid(row=0, column=0, columnspan=2, sticky="ew", **PAD)

        ttk.Label(frm_conn, text="COM port:").grid(row=0, column=0, **PAD)

        self.port_var = tk.StringVar()
        self.port_cb  = ttk.Combobox(frm_conn, textvariable=self.port_var,
                                     width=18, state="readonly")
        self.port_cb.grid(row=0, column=1, **PAD)

        self.btn_refresh = ttk.Button(frm_conn, text="↺", width=3,
                                      command=self._refresh_ports)
        self.btn_refresh.grid(row=0, column=2, **PAD)

        self.btn_connect = ttk.Button(frm_conn, text="Připojit",
                                      command=self._toggle_connect)
        self.btn_connect.grid(row=0, column=3, **PAD)

        self.lbl_status = ttk.Label(frm_conn, text="●  Odpojeno",
                                    foreground="gray")
        self.lbl_status.grid(row=0, column=4, padx=10)

        ttk.Label(frm_conn, text=f"{BAUD_RATE} Bd  8N1",
                  foreground="gray").grid(row=0, column=5, **PAD)

        # ── Nahrání souboru ─────────────────────────────────────────────────
        frm_file = ttk.LabelFrame(self.root, text="Nahrání programu")
        frm_file.grid(row=1, column=0, columnspan=2, sticky="ew", **PAD)

        self.file_var = tk.StringVar()
        ent_file = ttk.Entry(frm_file, textvariable=self.file_var, width=46,
                             state="readonly")
        ent_file.grid(row=0, column=0, **PAD)

        ttk.Button(frm_file, text="Vybrat .bin…",
                   command=self._pick_file).grid(row=0, column=1, **PAD)

        self.btn_upload = ttk.Button(frm_file, text="⬆  Nahrát (w)",
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
            ("▶  Start ($6000)",  self._cmd_start,   "green"),
            ("M  WozMon",         self._cmd_monitor,  None),
            ("^R Restart",        self._cmd_reset,    "red"),
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
            state="disabled"
        )
        self.txt_term.grid(row=0, column=0, columnspan=3, **PAD)

        # Barevné tagy
        self.txt_term.tag_config("tx",    foreground="#569cd6")   # odesílaný text
        self.txt_term.tag_config("info",  foreground="#6a9955")   # systémové zprávy
        self.txt_term.tag_config("error", foreground="#f44747")   # chyby
        self.txt_term.tag_config("prog",  foreground="#ce9178")   # průběh nahrávání

        # Vstupní řádka
        self.input_var = tk.StringVar()
        ent_input = ttk.Entry(frm_term, textvariable=self.input_var, width=50)
        ent_input.grid(row=1, column=0, padx=6, pady=(0, 4), sticky="ew")
        ent_input.bind("<Return>", self._send_line)

        ttk.Button(frm_term, text="Odeslat",
                   command=self._send_line).grid(row=1, column=1, padx=(0, 4))
        ttk.Button(frm_term, text="Vymazat",
                   command=self._clear_term).grid(row=1, column=2, padx=(0, 4))

        # Styly pro barevná tlačítka (jen vizuální hint, ttk je omezený)
        style = ttk.Style()
        style.configure("green.TButton", foreground="darkgreen")
        style.configure("red.TButton",   foreground="darkred")

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
        if self.ser and self.ser.is_open:
            self._disconnect()
        else:
            self._connect()

    def _connect(self):
        port = self.port_var.get()
        if not port:
            messagebox.showerror("Chyba", "Vyber COM port.")
            return
        try:
            self.ser = serial.Serial(
                port, BAUD_RATE,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.05
            )
            self.running = True
            threading.Thread(target=self._read_loop, daemon=True).start()

            self.lbl_status.config(text=f"●  {port}", foreground="green")
            self.btn_connect.config(text="Odpojit")
            self.btn_upload.config(state="normal")
            self._log(f"Připojeno: {port}  {BAUD_RATE} Bd 8N1\n", "info")
        except serial.SerialException as e:
            messagebox.showerror("Chyba připojení", str(e))

    def _disconnect(self):
        self.running = False
        if self.ser:
            try:
                self.ser.close()
            except Exception:
                pass
            self.ser = None
        self.lbl_status.config(text="●  Odpojeno", foreground="gray")
        self.btn_connect.config(text="Připojit")
        self.btn_upload.config(state="disabled")
        self._log("Odpojeno.\n", "info")

    # -----------------------------------------------------------------------
    # Čtení ze sériového portu (vlákno)
    # -----------------------------------------------------------------------
    def _read_loop(self):
        while self.running and self.ser and self.ser.is_open:
            try:
                data = self.ser.read(64)
                if data:
                    self.rx_queue.put(data)
            except serial.SerialException:
                break

    def _poll_rx(self):
        """Přesouvá data z rx_queue do terminálu – spouštěno z hlavního vlákna."""
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
    # Odeslání z vstupní řádky
    # -----------------------------------------------------------------------
    def _send_line(self, event=None):
        if not self._is_connected():
            return
        text = self.input_var.get()
        self.input_var.set("")
        if text:
            self.ser.write((text + "\r").encode("ascii", errors="replace"))
            self._log(text + "\n", "tx")

    def _send_byte(self, b: bytes):
        if self._is_connected():
            self.ser.write(b)

    # -----------------------------------------------------------------------
    # Příkazy bootloaderu
    # -----------------------------------------------------------------------
    def _cmd_start(self):
        if not self._is_connected():
            return
        self._send_byte(b"s")
        self._log("→ s  (spuštění z $6000)\n", "tx")

    def _cmd_monitor(self):
        if not self._is_connected():
            return
        self._send_byte(b"m")
        self._log("→ m  (EWOZ / WozMon)\n", "tx")

    def _cmd_reset(self):
        if not self._is_connected():
            return
        self._send_byte(b"\x12")        # Ctrl+R = $12
        self._log("→ ^R (soft restart)\n", "tx")

    # -----------------------------------------------------------------------
    # Výběr souboru
    # -----------------------------------------------------------------------
    def _pick_file(self):
        path = filedialog.askopenfilename(
            title="Vyber binární program",
            filetypes=[("Binární soubory", "*.bin"), ("Všechny soubory", "*.*")],
            initialdir=os.path.join(os.path.dirname(__file__), "..",
                                    "Firmware", "ramtest", "output")
        )
        if path:
            self.file_var.set(path)
            size = os.path.getsize(path)
            color = "black" if size == UPLOAD_SIZE else "red"
            self._log(
                f"Soubor: {os.path.basename(path)}  ({size} B"
                + ("" if size == UPLOAD_SIZE else f"  ≠ {UPLOAD_SIZE} B !")
                + ")\n",
                "info" if size == UPLOAD_SIZE else "error"
            )

    # -----------------------------------------------------------------------
    # Nahrání
    # -----------------------------------------------------------------------
    def _upload(self):
        if self._upload_in_progress:
            return
        if not self._is_connected():
            return

        path = self.file_var.get()
        if not path or not os.path.exists(path):
            messagebox.showerror("Chyba", "Nejprve vyber soubor .bin")
            return

        size = os.path.getsize(path)
        if size != UPLOAD_SIZE:
            messagebox.showerror(
                "Špatná velikost",
                f"Soubor musí mít přesně {UPLOAD_SIZE} B.\n"
                f"Tento soubor má {size} B."
            )
            return

        threading.Thread(target=self._do_upload, args=(path,),
                         daemon=True).start()

    def _do_upload(self, path: str):
        self._upload_in_progress = True
        self.root.after(0, self.btn_upload.config, {"state": "disabled"})

        try:
            with open(path, "rb") as f:
                data = f.read()

            # Odešli příkaz 'w' a krátce počkej na odpověď bootloaderu
            self.ser.write(b"w")
            self.root.after(0, self._log, "→ w  (čekám na bootloader…)\n", "tx")
            time.sleep(0.3)

            # Stream binárky po chunkcích
            sent = 0
            self.root.after(0, self.progress.config, {"value": 0})

            for i in range(0, len(data), CHUNK_SIZE):
                if not (self.ser and self.ser.is_open):
                    self.root.after(0, self._log, "Přenos přerušen – port zavřen.\n", "error")
                    return
                chunk = data[i:i + CHUNK_SIZE]
                self.ser.write(chunk)
                sent += len(chunk)

                # Aktualizuj progress bar (v hlavním vlákně)
                pct = sent * 100 // UPLOAD_SIZE
                self.root.after(0, self._update_progress, sent, pct)

            self.root.after(0, self._log,
                            f"Nahrání dokončeno ({sent} B). "
                            f"Bootloader spustí program automaticky.\n", "info")
            self.root.after(0, self.progress.config, {"value": UPLOAD_SIZE})
            self.root.after(0, self.lbl_progress.config, {"text": "100 %"})

        except Exception as e:
            self.root.after(0, self._log, f"Chyba při nahrávání: {e}\n", "error")
        finally:
            self._upload_in_progress = False
            self.root.after(0, self.btn_upload.config, {"state": "normal"})

    def _update_progress(self, sent: int, pct: int):
        self.progress.config(value=sent)
        self.lbl_progress.config(text=f"{pct} %")
        if pct % 10 == 0:
            self._log(f"  … {sent}/{UPLOAD_SIZE} B  ({pct} %)\n", "prog")

    # -----------------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------------
    def _is_connected(self) -> bool:
        if self.ser and self.ser.is_open:
            return True
        messagebox.showwarning("Nepřipojeno", "Nejprve se připoj k COM portu.")
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
