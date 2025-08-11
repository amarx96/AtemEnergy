
### Extracting SolarPV Data ###
### Import dependencies
include("Quarter_Hour_Interpolation.jl")
file_path ="C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\SolarPVKapFaktoren\\solar_cf_berlin_2024_timestamped.csv"
Solar_CF = readin(file_path,default=0, dims=1, dir=data_dir)

Solar_CF = interp_qh(Solar_CF)

Solar_CF = Dict(Solar_CF.Timestamp .=> Solar_CF.CapacityFactor)

Solar_CF = OrderedDict(sort(collect(Solar_CF), by=first))