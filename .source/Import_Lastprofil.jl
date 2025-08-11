using CSV
using DataFrames
using Dates
using CairoMakie
# Path to your CSV file
file_path = "C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Lastgang\\LG_DX_2023_geglättet.csv"

# Read the file with date parsing
df_load = CSV.read(file_path, DataFrame; dateformat="dd/mm/yyyy HH:MM", 
                   types=Dict(:Zeitstempel => DateTime))

# Rename columns (optional)
rename!(df_load, Dict(:Zeitstempel => :Timestamp, :Wert => :Load))

# Preview
first(df_load, 5)

# ================================
# Clean Outliers
# ================================
μ = mean(df_load.Load)
σ = std(df_load.Load)
threshold = μ + 3σ

df_clean = filter(:Load => x -> x <= threshold, df_load)

println("Ausreißer entfernt: ", nrow(df_load) - nrow(df_clean))

# ================================
# Print Load Profile
# ================================
# x-Achse: Unix-Sekunden (Float64)
x = Dates.datetime2unix.(df_clean.Timestamp)              # Vector{Float64}
y = Float64.(df_clean.Load)

fig = Figure(resolution = (1200, 400))
ax  = Axis(fig[1, 1], xlabel = "Zeit", ylabel = "Last [kW]", title = "Lastprofil 2024")

lines!(ax, x, y)

# Achsenticks als Datum formatieren
nticks = 10
ticks  = range(first(x), last(x), length = nticks) |> collect
labels = Dates.format.(Dates.unix2datetime.(ticks), dateformat"yyyy-mm-dd HH:MM")
ax.xticks = (ticks, labels)

# Maximalwert markieren (optional)
i = argmax(y)
scatter!(ax, [x[i]], [y[i]], color = :red)

fig

save("C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Ergebnisse\\DX_Center\\Lastprofil_2024.png", fig)


LoadProfile = Dict(df_clean.Timestamp .=> Float64.(df_clean.Load))




