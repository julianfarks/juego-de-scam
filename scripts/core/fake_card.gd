class_name FakeCard
extends RefCounted
## Tarjetas de MENTIRA para la pantalla de transacción. Son inservibles a propósito:
## - empiezan por 0000 (ningún emisor real usa ese prefijo),
## - el número falla siempre la comprobación de Luhn,
## - la fecha usa el mes 13 (no existe) y el CVV son letras.
## Nunca se piden ni se guardan datos financieros reales del jugador.

const BANKS := ["Banco de Mentirijillas", "Caja Rural de Patatonia", "Monopoli Bank", "Crédito Imaginario S.A.", "Banco del Charco"]
const BRANDS := ["FALSA", "NOCARD", "PATACARD", "CHISTEXPRESS"]


static func luhn_valid(number: String) -> bool:
	var digits := number.replace(" ", "")
	var total := 0
	var alt := false
	for i in range(digits.length() - 1, -1, -1):
		var n := int(digits[i])
		if alt:
			n *= 2
			if n > 9:
				n -= 9
		total += n
		alt = not alt
	return total % 10 == 0


static func generate(rng: RandomNumberGenerator, holder: String) -> Dictionary:
	var digits := "0000"
	for i in 12:
		digits += str(rng.randi_range(0, 9))
	if luhn_valid(digits):
		var last := (int(digits[15]) + 1) % 10
		digits = digits.substr(0, 15) + str(last)
	var grouped := "%s %s %s %s" % [digits.substr(0, 4), digits.substr(4, 4), digits.substr(8, 4), digits.substr(12, 4)]
	var letters := "XYZQWK"
	var cvv := ""
	for i in 3:
		cvv += letters[rng.randi() % letters.length()]
	return {
		"number": grouped,
		"masked": "0000 •••• •••• " + digits.substr(12, 4),
		"holder": holder,
		"expiry": "13/%02d" % rng.randi_range(90, 99),
		"cvv": cvv,
		"bank": BANKS[rng.randi() % BANKS.size()],
		"brand": BRANDS[rng.randi() % BRANDS.size()],
		"fictional": true,
	}


static func is_clearly_fake(card: Dictionary) -> bool:
	var n: String = card.get("number", "")
	return n.begins_with("0000") and not luhn_valid(n) and str(card.get("expiry", "")).begins_with("13/")
