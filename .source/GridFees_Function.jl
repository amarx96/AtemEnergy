# Netzentgelte
# Wähle Spalte: :netto oder :brutto
price_column = :brutto   # <— auf :brutto stellen, falls du die zweite Spalte willst

# Leistungspreis €/kW/Monat nach Kalendertagen
LP_EUR_kW_mon = Dict(
    28 => (netto=19.61, brutto=23.34),
    29 => (netto=19.61, brutto=23.34),
    30 => (netto=19.61, brutto=23.34),
    31 => (netto=19.61, brutto=23.34),
)


# Arbeitspreis ct/kWh (identisch für alle Monate laut Tabelle)
AP_ct_kWh = (netto=3.55, brutto=4.22)

# Helfer zum Spaltenzugriff
col(v) = getfield(v, price_column)