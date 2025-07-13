using JuMP # building models
using DataStructures # using dictionaries with a default value
using HiGHS # solver for the JuMP model
using CSV # readin of CSV files
using DataFrames # data tables
using Statistics # mean function
using Plots  # generate graphs
using Plots.Measures
using StatsPlots # additional features for plots
include(joinpath(@__DIR__, "colors.jl")) # colors for the plots
include(joinpath(@__DIR__, "helper_functions.jl")) # helper functions
using(Interpolations) # for interpolation of solar data
data_dir = joinpath(@__DIR__, "data")


### Read in of parameters ###
# We define our sets from the csv files
technologies = readcsv("technologies.csv", dir=data_dir).technology
fuels = readcsv("fuels.csv", dir=data_dir).fuel
storages = readcsv("storages.csv", dir=data_dir).storage
hour = 1:120
n_hour = length(hour)
regions = readcsv("regions.csv", dir=data_dir).region

# also, we need a set for our years
years = 2020:10:2050

# Also, we read our input parameters via csv files
Demand = readin("demand_regions.csv", dims=3, dir=data_dir)
OutputRatio = readin("outputratio.csv", dims=2, dir=data_dir)
InputRatio = readin("inputratio.csv", dims=2, dir=data_dir)
VariableCost = readin("variablecost.csv", dims=2, dir=data_dir)
InvestmentCost = readin("investmentcost.csv", dims=2, dir=data_dir)
EmissionRatio = readin("emissionratio.csv", dims=1, dir=data_dir)
DemandProfile = readin("demandprofile_regions.csv", default=1/n_hour, dims=3, dir=data_dir)
CapacityFactor = readin("capacity_factors_regions.csv",default=0, dims=3, dir=data_dir)
TagDispatchableTechnology = readin("tagdispatchabletechnology.csv",default=1,dims=1, dir=data_dir)

# we need to ensure that all non-variable technologies do have a CapacityFactor of 1 at all times
for r in regions    
    for t in technologies
        if TagDispatchableTechnology[t] > 0
            for h in hour
                CapacityFactor[r,h,t] = 1
            end
        end
    end
end

# we can test if solar does still produce during the night
CapacityFactor["DE",30,"SolarPV"]

### Also, we need to read in our additional storage parameters
InvestmentCostStorage = readin("investmentcoststorage.csv",dims=2, dir=data_dir)
E2PRatio = readin("e2pratio.csv",dims=1, dir=data_dir)
StorageChargeEfficiency = readin("storagechargeefficiency.csv",dims=2, dir=data_dir)
StorageDischargeEfficiency = readin("storagedischargeefficiency.csv",dims=2, dir=data_dir)
MaxStorageCapacity = readin("maxstoragecapacity.csv",default=50,dims=3, dir=data_dir)
StorageLosses = readin("storagelosses.csv",default=1,dims=2, dir=data_dir)

# our yearly emission limit
AnnualEmissionLimit = readin("annualemissionlimit.csv",default=999999,dims=1, dir=data_dir)

#our discount rate
DiscountRate = 0.05

# stuff for emission trajectories
ModelPeriodEmissionLimit = 600000

# create a multiplier to weight the different years correctly
YearlyDifferenceMultiplier = Dict()
for i in 1:length(years)-1
    difference = years[i+1] - years[i]
    YearlyDifferenceMultiplier[years[i]] = difference
end
YearlyDifferenceMultiplier[years[end]] = 1

# this gives us the distance between each year for all years
YearlyDifferenceMultiplier

# define the dictionary for max capacities with specific default value
MaxCapacity = readin("maxcapacity.csv", default=999, dims=3, dir=data_dir)
MaxTradeCapacity = readin("maxtradecapacity.csv", default=0, dims=4, dir=data_dir)

# add your trade distances and other trade parameters
TradeDistance = readin("tradedistance.csv",default=0,dims=2, dir=data_dir)
TradeCostFactor = readin("tradecostfactor.csv",default=0,dims=1, dir=data_dir)
TradeLossFactor = readin("tradelossfactor.csv",default=0,dims=1, dir=data_dir)

# Add residual capacity and Technology Lifetime
ResidualCapacity = readin("residualcapacity.csv",default=0,dims=3,dir=data_dir)
TechnologyLifetime = readin("technologylifetime.csv",default=10,dims=1,dir=data_dir)


### Extracting SolarPV Data ###
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