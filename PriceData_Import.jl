### Import Price DataFrame
using CSV # readin of CSV files
using DataFrames # data tables
using XLSX 
# Dateipfade anpassen

# Importiere Preise
# CSV-Dateien einlesen
pfad = "C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Strompreise"
df_da_preis    = DataFrame(XLSX.readtable(xlsx_path, "1")...)
df_ida_preis     = CSV.read(joinpath(pfad, "Index_Ausgleichsenergiepreis.csv"), DataFrame)
df_aep_preis     = CSV.read(joinpath(pfad, "AEP-Schaetzer.csv"), DataFrame)
df_rebap_ueb_preis = CSV.read(joinpath(pfad, "reBAP_ueberdeckt.csv"), DataFrame)
df_rebap_unter_preis = CSV.read(joinpath(pfad, "reBAP_unterdeckt.csv"), DataFrame)

# Importiere Ausgleichsenergie Nachfrage
# Importiere Demand CSVs laden
pfad = "C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Nachfrage_Regelenergie"
df_aep_module     = CSV.read(joinpath(pfad, "AEP_Module.csv"), DataFrame)
df_aep_schaetzer  = CSV.read(joinpath(pfad, "AEP-Schaetzer.csv"), DataFrame)
df_afrr           = CSV.read(joinpath(pfad, "aFRR_Nachfrage.csv"), DataFrame)
df_mfrr           = CSV.read(joinpath(pfad, "mFRR_Nachfrage.csv"), DataFrame)
df_prl            = CSV.read(joinpath(pfad, "PRL_Nachfrage.csv"), DataFrame)
df_preissetzer    = CSV.read(joinpath(pfad, "Preissetzendes_AEP_Modul.csv"), DataFrame)

# Importiere Lastprofil
# Load Excel file and sheet named "1"
xlsx_path = "C:/Users/alex-/Desktop/BatteryStorage/Optimization/strompreise/DayAhead_Prices.xlsx"
sheet = XLSX.readtable(xlsx_path, "1")
prices_da = DataFrame(XLSX.readtable(xlsx_path, "1")...)

# Beispiel: Daten vom 28.02.2023 kopieren für den Schalttag
tag_fuer_feb29 = Date(2023, 2, 28)
df_feb28 = filter(row -> Date(row.Zeit) == tag_fuer_feb29, df_2023)

# 1 Jahr aufschlagen und Jahr aktualisieren
df_feb29 = deepcopy(df_feb28)
df_feb29.Zeit .= df_feb29.Zeit .+ Year(1)
df_feb29.Jahr .= 2024

# An df_2024 anhängen und sortieren
tag_fuer_feb29 = Date(2023, 2, 28)
df_feb28  = filter(row -> Date(row.Zeit) == tag_fuer_feb29, df)

# 1 Jahr aufschlagen und Jahr aktualisieren
df_feb29 = deepcopy(df_feb28)
df_feb29.Zeit .= df_feb29.Zeit .+ Year(1)
df_feb29.Jahr .= 2024

# An df_2024 anhängen und sortieren
append!(df, df_feb29)
sort!(df, :Zeit)

# Länge der Zeitreihe
n_qh = nrow(df_aep)  # = 35136 bei Schaltjahr

# Neue Spalte 'QH_Index' hinzufügen
df_aep.QH_Index       = collect(1:n_qh)
df_rebap_ueb.QH_Index = collect(1:n_qh)
df_rebap_unter.QH_Index = collect(1:n_qh)   