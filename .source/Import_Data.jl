### Import Price DataFrame
# Dateipfade anpassen
pfad = "C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Strompreise"

# CSV-Dateien einlesen
df_aep_preis     = CSV.read(joinpath(pfad, "AEP-Schaetzer.csv"), DataFrame)
df_rebap_ueb_preis = CSV.read(joinpath(pfad, "reBAP_ueberdeckt.csv"), DataFrame)
df_rebap_unter_preis = CSV.read(joinpath(pfad, "reBAP_unterdeckt.csv"), DataFrame)

# CSVs laden
pfad = "C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Nachfrage_Regelenergie"
df_aep_module     = CSV.read(joinpath(pfad, "AEP_Module.csv"), DataFrame)
df_aep_schaetzer  = CSV.read(joinpath(pfad, "AEP-Schaetzer.csv"), DataFrame)
df_afrr           = CSV.read(joinpath(pfad, "aFRR_Nachfrage.csv"), DataFrame)
df_mfrr           = CSV.read(joinpath(pfad, "mFRR_Nachfrage.csv"), DataFrame)
df_prl            = CSV.read(joinpath(pfad, "PRL_Nachfrage.csv"), DataFrame)
df_preissetzer    = CSV.read(joinpath(pfad, "Preissetzendes_AEP_Modul.csv"), DataFrame)