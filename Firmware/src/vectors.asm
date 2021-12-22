
.setcpu		"65C02"
.smart		on
.autoimport	on
.case		on

.export _nmi_vec
.export _irq_vec
.export __OUTPUT, __INPUT

.segment "DATA"

_nmi_vec  = $300
_irq_vec  = $302

__OUTPUT  = $304
__INPUT   = $305
