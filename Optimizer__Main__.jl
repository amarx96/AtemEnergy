# Main Battery Optimizer
data_dir = joinpath(@__DIR__)

### Import dependencies
include(joinpath(@__DIR__, "install_and_import.jl")) # Install and import required packages
include(joinpath(@__DIR__, "Import_Energy_Data.jl")) # colors for the plots
include(joinpath(@__DIR__, "Import_CapacityFactor.jl"))
include(joinpath(@__DIR__, "Import_PriceData.jl"))
include(joinpath(@__DIR__, "Import_Lastprofil.jl"))
include(joinpath(@__DIR__, "colors.jl")) # colors for the plots
include(joinpath(@__DIR__, "helper_functions.jl")) # helper functions

# Prepare dictionaries
rename!(df_da_preis, Symbol("Sequence Sequence 1") => :Seq1, Symbol("Sequence Sequence 2") => :Seq2)
DayAheadPrices_Seq1 = Dict(row.timestamps => parse(Float64, row.Seq1) for row in eachrow(df_da_preis))
DayAheadPrices_Seq2 = Dict(row.timestamps => parse(Float64, row.Seq2) for row in eachrow(df_da_preis))

### Object Funciton
m = Model(HiGHS.Optimizer)

# === parameters ===
# Extract keys and values into vectors
Timestamps = collect(keys(Solar_CF))
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
@variable(m, TotalPVCost[technologies] >= 0)

### And we also need to add our new variables for storages
@variable(m, NewStorageEnergyCapacity[s=storages,f=fuels; StorageDischargeEfficiency[s,f]>0]>=0)
@variable(m, AccumulatedStorageEnergyCapacity[s=storages,f=fuels,Timestamps; StorageDischargeEfficiency[s,f]>0]>=0)
@variable(m, StorageCharge[s=storages, f=fuels,Timestamps; StorageDischargeEfficiency[s,f]>0]>=0)
@variable(m, StorageDischarge[s=storages, f=fuels,Timestamps; StorageDischargeEfficiency[s,f]>0]>=0)
@variable(m, StorageLevel[s=storages, f=fuels,Timestamps; StorageDischargeEfficiency[s,f]>0]>=0)
@variable(m, TotalStorageCost[storages] >= 0)

# Add Market variables
@variable(m, Purchased[Timestamps] >= 0)
@variable(m, PurchasedIDA[fuels, Timestamps] >= 0)
@variable(m, PurchasedDayAhead[fuels, Timestamps] >= 0)
@variable(m, PurchasedDayAhead_Seq1[Timestamps] >= 0)
@variable(m, PurchasedDayAhead_Seq2[Timestamps] >= 0)
@variable(m, PurchasingCost[Timestamps] >= 0)

# ================================ #
### Implement Objective Function ###
# ================================ #
@objective(m, Min, 
    sum(TotalPVCost[t] for t in technologies) + 
    sum(TotalStorageCost[s] for s in storages, τ in Timestamps) +
    sum(PurchasingCost[τ] for τ in Timestamps)
)

### Cost accounting
# PV Cost Function
@constraint(m, ProductionCost[t in technologies,τ in Timestamps],
    sum(FuelProductionByTechnology[t,f,τ] for f in fuels, τ in Timestamps) * VariableCost[2020,t] + NewCapacity[t] * InvestmentCost[2020,t] == TotalPVCost[t]
)

# Battery Cost Function
@constraint(m, StorageCostFunction[s in storages], 
    TotalStorageCost[s] == sum(NewStorageEnergyCapacity[s,f]*InvestmentCostStorage[2020,s] for f in fuels if StorageDischargeEfficiency[(s,f)]>0)
)

# Day-Ahead Market Cost Function
@constraint(m, PurchasingCostFunction[τ in Timestamps],
    PurchasingCost[τ] == PurchasedDayAhead_Seq1[τ] * DayAheadPrices_Seq1[τ] + 
                        PurchasedDayAhead_Seq2[τ] * DayAheadPrices_Seq2[τ]
)


# ================================ #
### Technical Constraints        ###
# ================================ #
@constraint(m, PurchasingFunction[τ in Timestamps],
    Purchased[τ] == PurchasedDayAhead_Seq1[τ] + PurchasedDayAhead_Seq1[τ]
)

### Demand Constraints: Grid
@constraint(m, DemandFunction[t in technologies, f in fuels, τ in Timestamps],
    FuelProductionByTechnology[t,f,τ] + sum(StorageDischarge[s,f,τ] for s in storages) + Purchased[τ] 
    == FuelUseByTechnology[t,f,τ] + sum(StorageCharge[s,f,τ] for s in storages) + Curtailment[f,τ]  +LoadProfile[f,τ]
)


### Implement PV Constraints ###
# for variable renewables, the production needs to be always at maximum
@constraint(m, ProductionFunction_res[t in technologies, f in fuels,τ in Timestamps;TagDispatchableTechnology[t]==0],
    OutputRatio[t,f] * AccumulatedCapacity[t] * Solar_CF[τ] == FuelProductionByTechnology[t,f,τ]
)

# define the use by the production
@constraint(m, UseFunction[t in technologies, f in fuels, τ in Timestamps],
    InputRatio[t,f] * sum(FuelProductionByTechnology[t,ff, τ] for ff in fuels) == FuelUseByTechnology[t,f, τ]
)

# installed capacity is limited by the maximum capacity
@constraint(m, MaxCapacityFunction[t in technologies, τ in Timestamps],
     AccumulatedCapacity[t] <= MaxCapacity[t]
)

### Implement Battery Constraints ###
@constraint(m, StorageChargeFunction[s in storages, f in fuels, τ in Timestamps; StorageDischargeEfficiency[s,f]>0], 
    StorageCharge[s,f,τ] <= AccumulatedStorageEnergyCapacity[s,f,τ]/E2PRatio[s]
)

@constraint(m, StorageDischargeFunction[s in storages, f in fuels, τ in Timestamps; StorageDischargeEfficiency[s,f]>0], 
    StorageDischarge[s,f,τ] <= AccumulatedStorageEnergyCapacity[s,f,τ]/E2PRatio[s]
)

for s in storages, f in fuels
    if StorageDischargeEfficiency[s, f] > 0
        for t = 2:length(Timestamps)  # skip first timestep
            τ = Timestamps[t]
            τ_prev = Timestamps[t-1]
            @constraint(m, 
                StorageLevel[s,f,τ] == 
                StorageLevel[s,f,τ_prev] * StorageLosses[s,f] + 
                StorageCharge[s,f,τ] * StorageChargeEfficiency[s,f] - 
                StorageDischarge[s,f,τ] / StorageDischargeEfficiency[s,f]
            )
        end
    end
end

@constraint(m, StorageLevelStartFunction[s in storages, f in fuels, τ in Timestamps; τ==Timestamps[1] && StorageDischargeEfficiency[s,f]>0], 
    StorageLevel[s,f,τ] == 0.5*AccumulatedStorageEnergyCapacity[s,f,τ]*StorageLosses[s,f] + StorageCharge[s,f,τ]*StorageChargeEfficiency[s,f] - StorageDischarge[s,f,τ]/StorageDischargeEfficiency[s,f]
)

@constraint(m, MaxStorageLevelFunction[s in storages, f in fuels, τ in Timestamps; StorageDischargeEfficiency[s,f]>0], 
    StorageLevel[s,f,τ] <= AccumulatedStorageEnergyCapacity[s,f,τ]
)

########### Total Installed capacity 
# calculate the total installed capacity in each year
@constraint(m, CapacityAccountingFunction[t in technologies],
    NewCapacity[t] == AccumulatedCapacity[t])

# account for currently installed storage capacities
@constraint(m, StorageCapacityAccountingFunction[s in storages, f in fuels, τ in Timestamps; StorageDischargeEfficiency[s,f]>0],
    NewStorageEnergyCapacity[s,f] == AccumulatedStorageEnergyCapacity[s,f,τ]
)



# this starts the optimization
# the assigned solver (here HiGHS) will takes care of the solution algorithm
optimize!(m)
termination_status(m)

f = "Power"
t = "SolarPV"
s = "Battery"


### Plotting
# Get time series data
fuel_production   = [value(FuelProductionByTechnology[t,f,τ]) for τ in Timestamps]
storage_discharge = [value(StorageDischarge[s,f,τ]) for τ in Timestamps]
purchased         = [value(Purchased[τ]) for τ in Timestamps]

# Area chart stack: Fuel supply sources
plot(
    Timestamps, 
    [fuel_production storage_discharge purchased],
    label=["Fuel Production" "Discharge" "Purchased"],
    seriestype=:area,
    fillalpha=0.5,
    lw=0.5,
    xlabel="Time", ylabel="MW",
    title="Supply Components (Area)",
    legend=:topright,
    size=(1000, 400)
)

# Calculate total demand
fuel_use       = [value(FuelUseByTechnology[t,f,τ]) for τ in Timestamps]  # Optional
storage_charge = [value(StorageCharge[s,f,τ]) for τ in Timestamps]
load           = [LoadProfile[(f,τ)] for τ in Timestamps]
total_demand   = storage_charge .+ load  # You can also include fuel_use if relevant

# Overlay total demand as line
plot!(
    Timestamps,
    total_demand,
    label="Total Demand (Charge + Load)",
    lw=2,
    linecolor=:black,
    seriestype=:line
)