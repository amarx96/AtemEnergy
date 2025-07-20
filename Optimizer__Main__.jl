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
# Extract and sort the timestamps
Timestamps_unsorted = collect(keys(Solar_CF))
Timestamps = sort(Timestamps_unsorted)

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


# Selling Variables
@variable(m, SellingDayAhead_Seq1[Timestamps] >= 0)
@variable(m, SellingDayAhead_Seq2[Timestamps] >= 0)
@variable(m, ProfitDayAhead[Timestamps] >= 0)

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
    PurchasingCost[τ] == PurchasedDayAhead_Seq1[τ] * DayAheadPrices_Seq1[τ] / 1000 # Converting EUR/MWh to EUR/kWh
                        + PurchasedDayAhead_Seq2[τ] * DayAheadPrices_Seq2[τ] / 1000 # Converting EUR/MWh to EUR/kWh
                        + (PurchasedDayAhead_Seq1[τ] + PurchasedDayAhead_Seq2[τ]) * 0.15 # Grid Fees in EUR/kWh
)


# Day-Ahead Market Cost Function
@constraint(m, SalesFunction[τ in Timestamps],
    ProfitDayAhead[τ] == SellingDayAhead_Seq1[τ] * DayAheadPrices_Seq1[τ] / 1000 # Converting EUR/MWh to EUR/kWh
                        + SellingDayAhead_Seq2[τ] * DayAheadPrices_Seq2[τ] / 1000 # Converting EUR/MWh to EUR/kWh
)


# ================================ #
### Technical Constraints        ###
# ================================ #
@constraint(m, PurchasingFunction[τ in Timestamps],
    Purchased[τ] == PurchasedDayAhead_Seq1[τ] + PurchasedDayAhead_Seq2[τ]
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


@constraint(m, MaxCapacityConstraint[t in technologies, f in fuels, τ in Timestamps],
        AccumulatedCapacity[t] <= 5000 # Maximum Solar Capacity below 5 MW
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
    StorageLevel[s,f,τ] >= 0.4*AccumulatedStorageEnergyCapacity[s,f,τ]*StorageLosses[s,f] + StorageCharge[s,f,τ]*StorageChargeEfficiency[s,f] - StorageDischarge[s,f,τ]/StorageDischargeEfficiency[s,f]
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
    AccumulatedStorageEnergyCapacity[s,f,τ] <= NewStorageEnergyCapacity[s,f]
)



# this starts the optimization
# the assigned solver (here HiGHS) will takes care of the solution algorithm
optimize!(m)
termination_status(m)

f = "Power"
t = "SolarPV"
s = "Battery"


### Plotting


# Convert DateTime to Float64 for plotting
t0 = minimum(Timestamps)
ts_float = Dates.value.(Timestamps) .- Dates.value(t0)  # elapsed nanoseconds
ts_float = ts_float ./ 1e9  # convert to seconds for easier interpretation

# Define tick formatter to show time labels
tick_labels = Timestamps[1:round(Int, length(Timestamps) / 10):end]
tick_positions = Dates.value.(tick_labels) .- Dates.value(t0)
tick_positions = tick_positions ./ 1e9

# Data
fp  = [value(FuelProductionByTechnology["SolarPV", "Power", τ]) for τ in Timestamps]
sd  = [value(StorageDischarge["Battery", "Power", τ]) for τ in Timestamps]
pur = [value(Purchased[τ]) for τ in Timestamps]
sc  = [value(StorageCharge["Battery", "Power", τ]) for τ in Timestamps]
load = [LoadProfile[("Power", τ)] for τ in Timestamps]
demand = sc .+ load

# Sorrt x axis for consistent plotting
sortperm_ts = sortperm(Timestamps)
Timestamps_sorted = Timestamps[sortperm_ts]
ts_float_sorted = ts_float[sortperm_ts]

# Downsample ticks for better readability
tick_stride = max(1, Int(length(Timestamps_sorted) ÷ 10))
tick_indices = 1:tick_stride:length(Timestamps_sorted)
tick_positions = ts_float_sorted[tick_indices]
tick_labels = string.(Timestamps_sorted[tick_indices])

using StatsBase
smoothed_fp = [mean(fp[max(1, i-2):min(end, i+2)]) for i in 1:length(fp)]
# Do the same for `sd`, `pur`, etc.

# Plot
fig = Figure(size = (1000, 400))
ax = Axis(fig[1, 1], title = "Supply and Demand", xlabel = "Time", ylabel = "MW")

band!(ax, ts_float_sorted, zeros(length(ts_float_sorted)), fp[sortperm_ts], color = (:cornflowerblue, 0.3), label = "Fuel Production")
band!(ax, ts_float_sorted, zeros(length(ts_float_sorted)), sd[sortperm_ts], color = (:orange, 0.3), label = "Discharge")
band!(ax, ts_float_sorted, zeros(length(ts_float_sorted)), pur[sortperm_ts], color = (:green, 0.3), label = "Purchased")

lines!(ax, ts_float_sorted, load[sortperm_ts], color = :black, linewidth = 2, label = "Total Demand")

ax.xticks = (tick_positions, tick_labels)
axislegend(ax, position = :rb)
fig