# Importiere Lastprofil
using CSV
using DataFrames    
# Also, we read our input parameters via csv files
# CSV einlesen mit korrektem Separator
lines = readlines("C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\LG_Strom_ab_2023.csv")
entries = Vector{Tuple{DateTime, Float64}}()

# Erkenne Datumszeit + Wert-Muster
pattern = r"(\d{2}\.\d{2}\.\d{4} \d{2}:\d{2});\s*(\d+(?:[.,]\d+)?)"

# Parsen jeder Zeile
for line in lines
    for m in eachmatch(pattern, line)
        dt_str = m.captures[1]
        val_str = replace(m.captures[2], ',' => '.')  # für deutsches Komma
        dt = DateTime(dt_str, dateformat"dd.mm.yyyy HH:MM")
        val = parse(Float64, val_str)
        push!(entries, (dt, val))
    end
end

# Erstelle DataFrame
df = DataFrame(Zeit=first.(entries), Leistung=last.(entries))
df.Jahr = year.(df.Zeit)
# Entferne die erste Zeile, da sie leer ist
df = df[df.Jahr .== 2023, :]

# Step 1: Turn Zeit into String and replace year
zeit_str = string.(df.Zeit)
zeit_str_replaced = replace.(zeit_str, "2023" => "2024")

# Step 2: Convert back to DateTime
df.Zeit = DateTime.(zeit_str_replaced)


df_Summary = combine(groupby(df, :Jahr),
    :Leistung => sum => :Summe_kW,
    :Leistung => length => :Anzahl_Einträge)

# Nur Einträge mit Uhrzeit (HH:MM)
function has_time_format(s::String)
    occursin(r"\d{2}/\d{2}/\d{4} \d{2}:\d{2}", s)
end

# Function to check if the string contains a timestamp
function has_time_component(s::String)
    occursin(r"\d{2}/\d{2}/\d{4} \d{2}:\d{2}", s)
end

# Convert timestamp string to Int index (number of 15-min intervals)
function to_quarter_index(s::String)
    dt = DateTime(s, dateformat"dd/mm/yyyy HH:MM")
    return Int(Dates.value(dt - reference_dt) ÷ (15 * 60_000))  # 15 minutes in ms
end


# Optional: Convert timestamp back to DateTime
# 3. Plot the demand time series
plot(df.Zeit, df.Leistung, xlabel="Zeit", ylabel="Last in MW", title="Lastprofil DX Center", lw=2)
# Beispiel: Daten vom 28.02.2023 kopieren für den Schalttag
tag_fuer_feb29 = Date(2024, 2, 28)
df_feb28 = filter(row -> Date(row.Zeit) == tag_fuer_feb29, df)

# An df_2023 anhängen und sortieren
tag_fuer_feb29 = Date(2023, 2, 28)
df_feb28  = filter(row -> Date(row.Zeit) == tag_fuer_feb29, df)

# An df_2024 anhängen und sortieren
append!(df, df_feb29)
df.Zeit = [DateTime(2024, month(z), day(z), hour(z), minute(z)) for z in df.Zeit]
df.Jahr .= 2024

sort!(df, :Zeit)



# Build the dictionary with keys as (fuel, timestamp) tuples
LoadProfile = Dict(("Power", row.Zeit) => row.Leistung for row in eachrow(df))



