
### Extracting SolarPV Data ###
### Import dependencies
using Interpolations
CapacityFactor = readin("capacity_factors_regions.csv",default=0, dims=3, dir=data_dir)

# Assuming your_dict is a dictionary with keys as tuples (Region, Hour, Technology)
# Filter all entries where the technology is "SolarPV"
solar_entries = filter(((k, v),) -> k[1]=="DE" && k[3] == "SolarPV", pairs(CapacityFactor))

# Turn into a DataFrame
df_solar = DataFrame(
    Region = getindex.(keys(solar_entries), 1),
    Hour = getindex.(keys(solar_entries), 2),
    Technology = getindex.(keys(solar_entries), 3),
    CapacityFactor = collect(values(solar_entries))
)

8760 / nrow(df_solar) 
# And you want timestamps for 2024
base_time = DateTime("2024-01-01T00:00:00")
df_solar.Timestamp = base_time .+ Hour.(df_solar.Hour .- 1)

# 1. Sort the original hourly DataFrame by Timestamp
sort!(df_solar, :Timestamp)

# 2. Create interpolation object
itp = LinearInterpolation(
    Dates.value.(df_solar.Timestamp),  # convert DateTime to Int64
    df_solar.CapacityFactor,
    extrapolation_bc=Line()
)

# 3. Generate 15-min timestamps
start_time = minimum(df_solar.Timestamp)
end_time = maximum(df_solar.Timestamp)
timestamps_15min = collect(start_time:Minute(15):end_time)

# 4. Interpolate capacity factors at 15-min resolution
cf_15min = itp.(Dates.value.(timestamps_15min))

# 5. Create interpolated DataFrame
df_interp = DataFrame(
    Timestamp = timestamps_15min,
    CapacityFactor = cf_15min
)

Solar_CF = Dict(row.Timestamp => row.CapacityFactor for row in eachrow(df_interp))