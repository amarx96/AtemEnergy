# Main Battery Optimizer


### Import dependencies
include(joinpath(@__DIR__, "install_and_import.jl")) # Install and import required packages
include(joinpath(@__DIR__, "Import_Energy_Data.jl")) # colors for the plots
include(joinpath(@__DIR__, "Import_CapacityFactor.jl"))
include(joinpath(@__DIR__, "Import_PriceData.jl"))
include(joinpath(@__DIR__, "Import_Lastprofil.jl"))

### Object Funciton
m = Model(HiGHS.Optimizer)

# === parameters ===
Timestamps = df_solar_cf.Timestamp
technologies = ["SolarPV"]
storages = ["Battery"]
fuels = ["Power"]

# And a Dict of maximum capacities in MW
MaxCapacity = Dict("SolarPV" => 5.0, "Battery" => 5.0)

η_charge = 0.95  # Efficiency of charging
η_discharge = 0.95  # Efficiency of discharging


### building the model ###
# instantiate a model with an optimizer
m = Model(HiGHS.Optimizer)

# PV Data
@variable(m, TotalCost[technologies] >= 0)
@variable(m, FuelProductionByTechnology[technologies, fuels, Timestamps] >= 0)
@variable(m, NewCapacity[technologies] >=0)
@variable(m, AccumulatedCapacity[technologies] >=0)
@variable(m, FuelUseByTechnology[technologies, fuels,Timestamps] >=0)
@variable(m, Curtailment[fuels,Timestamps] >=0)

### And we also need to add our new variables for storages
@variable(m, NewStorageEnergyCapacity[s=storages,f=fuels, Timestamps; StorageDischargeEfficiency[s,f]>0]>=0)
@variable(m, AccumulatedStorageEnergyCapacity[s=storages,f=fuels,Timestamps; StorageDischargeEfficiency[s,f]>0]>=0)
@variable(m, StorageCharge[s=storages, f=fuels,Timestamps; StorageDischargeEfficiency[s,f]>0]>=0)
@variable(m, StorageDischarge[s=storages, f=fuels,Timestamps; StorageDischargeEfficiency[s,f]>0]>=0)
@variable(m, StorageLevel[s=storages, f=fuels,Timestamps; StorageDischargeEfficiency[s,f]>0]>=0)
@variable(m, TotalStorageCost[storages,Timestamps] >= 0)


### Implement Constraints ###
# calculate the total cost
@constraint(m, ProductionCost[t in technologies,τ in Timestamps],
    sum(FuelProductionByTechnology[t,f,τ] for f in fuels, τ in Timestamps) * VariableCost[2020,t] + NewCapacity[t] * InvestmentCost[2020,t] == TotalCost[t]
)

# for variable renewables, the production needs to be always at maximum
@constraint(m, ProductionFunction_res[t in technologies, f in fuels,τ in Timestamps;TagDispatchableTechnology[t]==0],
    OutputRatio[t,f] * AccumulatedCapacity[t] * Solar_CF[τ] == FuelProductionByTechnology[t,f,τ]
)

# define the use by the production
@constraint(ESM, UseFunction[y in year,r in regions,h in hour,t in technologies, f in fuels],
    InputRatio[t,f] * sum(FuelProductionByTechnology[y,r,h,t,ff] for ff in fuels) == FuelUseByTechnology[y,r,h,t,f]
)

# installed capacity is limited by the maximum capacity
@constraint(ESM, MaxCapacityFunction[t in technologies, τ in Timestamps],
     AccumulatedCapacity[t] <= MaxCapacity[t]
)

### Add your storage constraints here
    @constraint(ESM, StorageChargeFunction[y in year,r in regions,s in storages, h in hour, f in fuels; StorageDischargeEfficiency[s,f]>0], 
    StorageCharge[y,r,s,h,f] <= AccumulatedStorageEnergyCapacity[y,r,s,f]/E2PRatio[s]
)

@constraint(ESM, StorageDischargeFunction[y in year,r in regions,s in storages, h in hour, f in fuels; StorageDischargeEfficiency[s,f]>0], 
    StorageDischarge[y,r,s,h,f] <= AccumulatedStorageEnergyCapacity[y,r,s,f]/E2PRatio[s]
)

@constraint(ESM, StorageLevelFunction[y in year,r in regions,s in storages, h in hour, f in fuels; h>1 && StorageDischargeEfficiency[s,f]>0], 
    StorageLevel[y,r,s,h,f] == StorageLevel[y,r,s,h-1,f]*StorageLosses[s,f] + StorageCharge[y,r,s,h,f]*StorageChargeEfficiency[s,f] - StorageDischarge[y,r,s,h,f]/StorageDischargeEfficiency[s,f]
)

@constraint(ESM, StorageLevelStartFunction[y in year,r in regions,s in storages, h in hour, f in fuels; h==1 && StorageDischargeEfficiency[s,f]>0], 
    StorageLevel[y,r,s,h,f] == 0.5*AccumulatedStorageEnergyCapacity[y,r,s,f]*StorageLosses[s,f] + StorageCharge[y,r,s,h,f]*StorageChargeEfficiency[s,f] - StorageDischarge[y,r,s,h,f]/StorageDischargeEfficiency[s,f]
)

@constraint(ESM, MaxStorageLevelFunction[y in year,r in regions,s in storages, h in hour, f in fuels; StorageDischargeEfficiency[s,f]>0], 
    StorageLevel[y,r,s,h,f] <= AccumulatedStorageEnergyCapacity[y,r,s,f]
)