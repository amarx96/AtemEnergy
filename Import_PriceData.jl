### Import Price DataFrame
using CSV # readin of CSV files
using DataFrames # data tables
using XLSX 
# Dateipfade anpassen

# Importiere Preise
pfad = "C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Strompreise"
df_da_preis = DataFrame(XLSX.readtable(joinpath(pfad, "DayAhead_Prices.xlsx"), "1")...)
df_ida_preis     = CSV.read(joinpath(pfad, "Index_Ausgleichsenergiepreis.csv"), DataFrame)
df_aep_preis     = CSV.read(joinpath(pfad, "AEP-Schaetzer.csv"), DataFrame)
df_rebap_ueb_preis = CSV.read(joinpath(pfad, "reBAP_ueberdeckt.csv"), DataFrame)
df_rebap_unter_preis = CSV.read(joinpath(pfad, "reBAP_unterdeckt.csv"), DataFrame)

# Importiere Ausgleichsenergie Nachfrage
# Importiere Demand CSVs laden
pfad = "C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Nachfrage_Regelenergie"
df_aep_module     = CSV.read(joinpath(pfad, "AEP_Module.csv"), DataFrame,delim=";")
df_aep_schaetzer  = CSV.read(joinpath(pfad, "AEP-Schaetzer.csv"), DataFrame, delim=";")
df_afrr           = CSV.read(joinpath(pfad, "aFRR_Nachfrage.csv"), DataFrame, delim=";")
df_mfrr           = CSV.read(joinpath(pfad, "mFRR_Nachfrage.csv"), DataFrame,   delim=";")
df_prl            = CSV.read(joinpath(pfad, "PRL_Nachfrage.csv"), DataFrame,delim=";")
df_preissetzer    = CSV.read(joinpath(pfad, "Preissetzendes_AEP_Modul.csv"), DataFrame,delim=";")



# Creating CET Time Stamps for Quantitiy Data
df_aep_module.timestamps = DateTime.(df_aep_module.Datum .* " " .* string.(df_aep_module.von), dateformat"dd.mm.yyyy HH:MM:SS")
df_rebap_ueb_preis.timestamps = DateTime.(df_rebap_ueb_preis.Datum .* " " .* string.(df_rebap_ueb_preis.von), dateformat"dd.mm.yyyy HH:MM:SS")
df_rebap_ueb_preis.timestamps = DateTime.(df_rebap_ueb_preis.Datum .* " " .* string.(df_rebap_ueb_preis.von), dateformat"dd.mm.yyyy HH:MM:SS")
df_aep_schaetzer.timestamps = DateTime.(df_aep_schaetzer.Datum .* " " .* string.(df_aep_schaetzer.von), dateformat"dd.mm.yyyy HH:MM:SS")

df_afrr.timestamps = DateTime.(df_afrr.Datum .* " " .* string.(df_afrr.von), dateformat"dd.mm.yyyy HH:MM:SS")
df_mfrr.timestamps = DateTime.(df_mfrr.Datum .* " " .* string.(df_mfrr.von), dateformat"dd.mm.yyyy HH:MM:SS")
df_prl.timestamps = DateTime.(df_prl.Datum .* " " .* string.(df_prl.von), dateformat"dd.mm.yyyy HH:MM:SS")

# Create DateTime vector from Date and Time strings
df_preissetzer.von = replace.(df_preissetzer.von, r"[AB]" => "")
df_preissetzer.timestamps = DateTime.(string.(df_preissetzer.Datum) .* " " .* df_preissetzer.von,dateformat"yyyy-mm-dd HH:MM")


# Creating CET Time Stamps for Pricing Datadf_ida_preis.timestamps = DateTime.(df_ida_preis."Datum von" .* " " .* string.(df_ida_preis."(Uhrzeit) von"), dateformat"dd.mm.yyyy HH:MM:SS")
df_ida_preis.timestamps = DateTime.(df_ida_preis."Datum von" .* " " .* string.(df_ida_preis."(Uhrzeit) von"), dateformat"dd.mm.yyyy HH:MM:SS")
df_da_preis.timestamps = DateTime.(replace.(first.(split.(String.(df_da_preis.Slot), " - ")), r" \([A-Z]+\)" => ""),     dateformat"dd/MM/yyyy HH:MM:SS")
df_aep_preis.timestamps = DateTime.(df_ida_preis."Datum von" .* " " .* string.(df_ida_preis."(Uhrzeit) von"), dateformat"dd.mm.yyyy HH:MM:SS")
df_rebap_ueb_preis.timestamps = DateTime.(df_ida_preis."Datum von" .* " " .* string.(df_ida_preis."(Uhrzeit) von"), dateformat"dd.mm.yyyy HH:MM:SS")
df_rebap_unter_preis.timestamps = DateTime.(df_ida_preis."Datum von" .* " " .* string.(df_ida_preis."(Uhrzeit) von"), dateformat"dd.mm.yyyy HH:MM:SS")