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

# And a Dict of maximum capacities in kW
MaxCapacity = Dict("SolarPV" => 3000, "Battery" => 5000)

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
@variable(m, TotalPowerSold[Timestamps] >= 0)

# Selling Variables
@variable(m, SellingDayAhead_Seq1[Timestamps] >= 0)
@variable(m, SellingDayAhead_Seq2[Timestamps] >= 0)
@variable(m, ProfitDayAhead[Timestamps] >= 0)

# ================================ #
### Implement Objective Function ###
# ================================ #
# ================================ #
### Implement Objective Function ###
# ================================ #
@objective(m, Max, 
    sum(ProfitDayAhead[τ] for τ in Timestamps)  # Profits from Trading
    - sum(TotalPVCost[t] for t in technologies) + 
    - sum(TotalStorageCost[s] for s in storages)
    - sum(PurchasingCost[τ] for τ in Timestamps)
)

### Cost accounting
# PV Cost Function
@constraint(m, ProductionCostFunction[t in technologies,τ in Timestamps],
    sum(FuelProductionByTechnology[t,f,τ] for f in fuels) * VariableCost[2020,t] * 1000 + InvestmentCost[2020,t]/ 15 * NewCapacity[t] == TotalPVCost[t] # Ignoring investment Cost for now
)

# Battery Cost, 300 EUR per kWh with 15 years of lifetime
@constraint(m, StorageCostFunction[s in storages], 
    TotalStorageCost[s] == sum(NewStorageEnergyCapacity[s,f] * 300/15 for f in fuels if StorageDischargeEfficiency[(s,f)]>0)
)

# Day-Ahead Market Cost Function
@constraint(m, PurchasingCostFunction[τ in Timestamps],
    PurchasingCost[τ] == PurchasedDayAhead_Seq1[τ] * DayAheadPrices_Seq1[τ] + 
                        PurchasedDayAhead_Seq2[τ] * DayAheadPrices_Seq2[τ]
)

# Day-Ahead Market Cost Function
@constraint(m, SalesFunction[τ in Timestamps],
    ProfitDayAhead[τ] == SellingDayAhead_Seq1[τ] * DayAheadPrices_Seq1[τ] / 1000 # Converting EUR/MWh to EUR/kWh
                        + SellingDayAhead_Seq2[τ] * DayAheadPrices_Seq2[τ] / 1000 # Converting EUR/MWh to EUR/kWh
)

# Sum Quantities Sold:
@constraint(m, TotalQuantitiesSold[τ in Timestamps],
    TotalPowerSold[τ]== SellingDayAhead_Seq1[τ] + SellingDayAhead_Seq2[τ])


# ================================ #
### Technical Constraints        ###
# ================================ #
@constraint(m, PurchasingFunction[τ in Timestamps],
    Purchased[τ] == PurchasedDayAhead_Seq1[τ] + PurchasedDayAhead_Seq1[τ]
)

### Energy Balance Constraints ###
@constraint(m, EnergyBalanceFunction[f in fuels, τ in Timestamps],
    sum(FuelProductionByTechnology[t,f,τ] for t in technologies) + StorageDischarge["Battery",f,τ]  + Purchased[τ]     # Production
    == StorageCharge["Battery",f,τ] + LoadProfile[f,τ] + Curtailment[f,τ] # Demand
    +  SellingDayAhead_Seq1[τ] + SellingDayAhead_Seq2[τ]                   # IDA
)

@constraint(m, MaxSales[τ in Timestamps],
    SellingDayAhead_Seq1[τ] + SellingDayAhead_Seq2[τ] <=
    sum(FuelProductionByTechnology[t,f,τ] for t in technologies, f in fuels) +
    sum(StorageDischarge[s,f,τ] for s in storages, f in fuels)
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

# Calculate total demand
fuel_use       = [value(FuelUseByTechnology[t,f,τ]) for τ in Timestamps]  # Optional
storage_charge = [value(StorageCharge[s,f,τ]) for τ in Timestamps]
load           = [LoadProfile[(f,τ)] for τ in Timestamps]
total_demand   = storage_charge .+ load  # You can also include fuel_use if relevant

import Pkg
Pkg.add("StatsPlots")  # Only once
plotlyjs()  # switch backend to PlotlyJS
using StatsPlots
plotlyjs()  # or pyplot()

# --- your time series data ---
# fuel_production, storage_discharge, purchased = vectors of length Timestamps
# total_demand = load + storage_charge

supply_sources = hcat(fuel_production, storage_discharge, purchased)  # shape: T × 3

using Plots
gr()

# Construct manual stacked areas:
s1 = fuel_production
s2 = s1 .+ storage_discharge
s3 = s2 .+ purchased

# Create a sorted index 
sorted_idx = sortperm(Timestamps)

# Sort all time series by the same index
sorted_timestamps      = Timestamps[sorted_idx]
sorted_fp              = fuel_production[sorted_idx]
sorted_sd              = storage_discharge[sorted_idx]
sorted_pp              = purchased[sorted_idx]
sorted_total_demand    = total_demand[sorted_idx]

# Plot with sorted data
plot(
    sorted_timestamps, 
    sorted_fp, 
    fillrange=0,
    label="Fuel Production",
    lw=0.5,
    fillalpha=0.5,
    c=:lightblue
)
plot!(
    sorted_timestamps,
    sorted_fp .+ sorted_sd,
    fillrange=sorted_fp,
    label="Discharge",
    lw=0.5,
    fillalpha=0.5,
    c=:khaki
)
plot!(
    sorted_timestamps,
    sorted_fp .+ sorted_sd .+ sorted_pp,
    fillrange=sorted_fp .+ sorted_sd,
    label="Purchased",
    lw=0.5,
    fillalpha=0.5,
    c=:darkseagreen
)
plot!(
    sorted_timestamps,
    sorted_total_demand,
    label="Total Demand",
    lw=2,
    linecolor=:black
)



using Plots
using StatsBase  # For smoothing
gr()  # Set GR as backend

# -- 1. Sort Timestamps and data --
sorted_idx = sortperm(Timestamps)

ts_sorted = Timestamps[sorted_idx]
fp_sorted = fuel_production[sorted_idx]
sd_sorted = storage_discharge[sorted_idx]
pp_sorted = purchased[sorted_idx]
demand_sorted = total_demand[sorted_idx]

# Optional: smooth total demand (removes jagged noise)
window = 5  # must be odd
halfwin = div(window, 2)
n = length(demand_sorted)

demand_smooth = [ mean(demand_sorted[max(1, i - halfwin):min(n, i + halfwin)]) for i in 1:n ]

# -- 2. Prepare cumulative layers for fillrange stacking --
s1 = fp_sorted
s2 = s1 .+ sd_sorted
s3 = s2 .+ pp_sorted

# -- 3. Plot stacked area chart --
p = plot(
    ts_sorted, s1,
    fillrange=0,
    label="Fuel Production",
    lw=0.5,
    fillalpha=0.4,
    color=:skyblue,
    xlabel="Time",
    ylabel="Power (MW)",
    title="Supply and Demand (Stacked)",
    legend=:topright,
    legend_background_color=:white,
    size=(1000, 400),
    grid=true,
    xrotation=30,
)

plot!(
    ts_sorted, s2,
    fillrange=s1,
    label="Discharge",
    lw=0.5,
    fillalpha=0.4,
    color=:gold,
)

plot!(
    ts_sorted, s3,
    fillrange=s2,
    label="Purchased",
    lw=0.5,
    fillalpha=0.4,
    color=:seagreen,
)

# -- 4. Overlay smoothed demand line --
plot!(
    ts_sorted, demand_smooth,
    label="Total Demand",
    lw=2,
    color=:black,
)

# -- 5. Save (optional) --
# savefig(p, "supply_demand_plot.pdf")
# savefig(p, "supply_demand_plot.png")

display(p)