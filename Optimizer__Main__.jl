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

rename!(df_ida_preis, Symbol("ID AEP in €/MWh") => :IDA_Price)
IntradayPrices = Dict(
    row.timestamps => parse(Float64, replace(String(row.IDA_Price), "," => "."))
    for row in eachrow(df_ida_preis)
)

# ========================= #
# === Capex Calculation === #
# ========================= #

# Define the annuity function
function annuity_factor(discount_rate::Float64, lifetime::Int)
    return (discount_rate / (1 - (1 + discount_rate)^(-lifetime)))
end


# === parameters ===
# Extract keys and values into vectors
sort(LoadProfile)
Timestamps = collect(keys(Solar_CF))

time_step = 15 / 60 # Time step in minutes

technologies = ["SolarPV"]
storages = ["Battery"]
fuels = ["Power"]


η_charge = 0.95  # Efficiency of charging
η_discharge = 0.9  # Efficiency of discharging

# Calculate the annualized cost of solar PV
solar_capex = 700  # in EUR/kW
battery_capex = 170  # in EUR/kWh

# Calculate the annualized cost of solar PV
annualized_solar_cost = solar_capex * annuity_factor(0.05, 20)   # in EUR/kWh/year
println("Annualized solar CAPEX cost: €$(round(annualized_solar_cost, digits=2))/kWh/year")

# Calculate the annualized cost of battery storage
annualized_battery_cost = batter_capex * annuity_factor(0.05, 15)  # in EUR/kWh/year
println("Annualized battery CAPEX cost: €$(round(annualized_battery_cost, digits=2))/kWh/year")


# And a Dict of maximum capacities in kW
MaxCapacity = Dict("SolarPV" => 3000, "Battery" => 5000)

# Maximum Netzanschluss leistung
MaxGridConnection = 5000  # in kW


### building the model ###
# instantiate a model with an optimizer
m = Model(HiGHS.Optimizer)

# PV Data
@variable(m, TotalCostSolarPV>= 0)
@variable(m, SolarPVProduction[Timestamps] >= 0)
@variable(m, NewSolarCapacity>=0)
@variable(m, AccumulatedSolarCapacity >=0)
@variable(m, Curtailment[Timestamps] >=0)
@variable(m, TotalPVCost >= 0)

### And we also need to add our new variables for storages
@variable(m, NewStorageEnergyCapacity>=0)
@variable(m, AccumulatedStorageEnergyCapacity>=0)
@variable(m, StorageCharge[Timestamps]>=0)
@variable(m, StorageDischarge[Timestamps]>=0)
@variable(m, StorageLevel[Timestamps]>=0)
@variable(m, TotalStorageCost >= 0)

# Add Market variables
@variable(m, MaxTariff[Timestamps] >= 0)
@variable(m, PowerPurchased[Timestamps] >= 0)
@variable(m, PurchasedIDA[Timestamps] >= 0)

@variable(m, PurchasedDayAhead[fuels, Timestamps] >= 0)
@variable(m, PurchasedDayAhead_Seq1[Timestamps] >= 0)
@variable(m, PurchasedDayAhead_Seq2[Timestamps] >= 0)
@variable(m, PurchasingCost[Timestamps] >= 0)
@variable(m, PowerSold[Timestamps] >= 0)

# Selling Variables
# Day-Ahead Market 
@variable(m, SellingDayAhead_Seq1[Timestamps] >= 0)
@variable(m, SellingDayAhead_Seq2[Timestamps] >= 0)
@variable(m, RevenueDayAhead[Timestamps] >= 0)

# Intra-Day Market
@variable(m, SellingIntraDay[Timestamps] >= 0)
@variable(m, RevenueIntraDay[Timestamps] >= 0)

# ======================== #
### Netzentgelte und Stromsteuer ###
Netzentgelte_EUR_kWh = 0.15 # Netzentgelte in EUR/kWh
StromSteuer_EUR_kWh = 0.02 # Stromsteuer in EUR/kWh
Marge_EUR_kWh = 0.02 # Marge in EUR/kWh

# ================================ #
### Implement Objective Function ###
# ================================ #
# Maximizing the difference between cost of Battery + PV and Sport-Tariff Procurement
@objective(m, Max, 
   sum(RevenueDayAhead[τ] for τ in Timestamps)  # Profits from Trading Day Ahead
  + sum(RevenueIntraDay[τ] for τ in Timestamps)  # Profits from Intra-Day Trading
    - TotalPVCost
    - TotalStorageCost
    - sum(PurchasingCost[τ] for τ in Timestamps))

# ================================ #
# Define the Spot Market Prices
# ================================ #    
@constraint(m, [τ in Timestamps], MaxTariff[τ] >= DayAheadPrices_Seq1[τ])
@constraint(m, [τ in Timestamps], MaxTariff[τ] >= DayAheadPrices_Seq2[τ])

### Profit and Loss Accounting
### Investment Kosten in EUR/KWh
@constraint(m, ProductionCostFunction,
    sum(SolarPVProduction[τ] * 0.01/4 for τ in Timestamps) + annualized_solar_cost * 120/8760 * NewSolarCapacity == TotalPVCost
)

# Battery Cost, 250 EUR per kWh with 15 years of lifetime
@constraint(m, StorageCostFunction, 
    TotalStorageCost == NewStorageEnergyCapacity * annualized_battery_cost * 120/8760)

# Day-Ahead Market Cost Function
# Einnahmen in EUR/KWh
@constraint(m, PurchasingCostFunction[τ in Timestamps],
    PurchasingCost[τ] ==(PurchasedDayAhead_Seq1[τ] * DayAheadPrices_Seq1[τ] / 1000 + 
                        PurchasedDayAhead_Seq2[τ] * DayAheadPrices_Seq2[τ] / 1000
                        + (PurchasedDayAhead_Seq1[τ] + PurchasedDayAhead_Seq2[τ]) 
                        * (Netzentgelte_EUR_kWh + StromSteuer_EUR_kWh + Marge_EUR_kWh) ) 
                        * time_step # Converting kW/ 15/60 h to EUR/kWh
)

# Day-Ahead Revenue Function
@constraint(m, SalesFunction[τ in Timestamps],
    RevenueDayAhead[τ] == (SellingDayAhead_Seq1[τ] * DayAheadPrices_Seq1[τ] / 1000 # Converting EUR/MWh to EUR/kWh
                        + SellingDayAhead_Seq2[τ] * DayAheadPrices_Seq2[τ] / 1000) # Converting EUR/MWh to EUR/kWh
                        * time_step 
)

# Intraday Market Revenue Function
@constraint(m, SalesFunctionIntraDay[τ in Timestamps],
    RevenueIntraDay[τ] ==
        SellingIntraDay[τ] * IntradayPrices[τ] / 1000 * time_step # Converting EUR/MWh to EUR/kWh
)


# ================================ #
### Technical Constraints        ###
# ================================ #
@constraint(m, PurchasingFunction[τ in Timestamps],
    PowerPurchased[τ] == PurchasedDayAhead_Seq1[τ] + PurchasedDayAhead_Seq2[τ]
)

@constraint(m, SellingFunction[τ in Timestamps],
    PowerSold[τ] == SellingIntraDay[τ] + SellingDayAhead_Seq1[τ] + SellingDayAhead_Seq2[τ]
)

### Energy Balance Constraints ###
@constraint(m, EnergyBalanceFunction[τ in Timestamps],
   SolarPVProduction[τ]  
    + StorageDischarge[τ]
    + PowerPurchased[τ]
    ==
    StorageCharge[τ]
    + LoadProfile[τ]
    + Curtailment[τ]
    + PowerSold[τ]
)

@constraint(m, CurtailmentLimit[τ in Timestamps],
    Curtailment[τ] <= SolarPVProduction[τ]
)

@constraint(m, MaxGridConnectionFunction[τ in Timestamps],
     PowerSold[τ] + PowerPurchased[τ] <= MaxGridConnection # Maximum grid connection capacity
)

# ================================ #
### Solar PV Constraints        ###
# ================================ #
# for variable renewables, the production needs to be always at maximum
@constraint(m, ProductionFunction_res[τ in Timestamps],
    AccumulatedSolarCapacity * Solar_CF[τ] ==  SolarPVProduction[τ]
)

# installed capacity is limited by the maximum capacity
@constraint(m, MaxCapacityFunction[τ in Timestamps],
     AccumulatedSolarCapacity <= 5000 # Maximum capacity 5 MW
)

# calculate the total installed capacity in each year
@constraint(m, CapacityAccountingFunction[τ in Timestamps],
    NewSolarCapacity .== AccumulatedSolarCapacity)

# ================================ #
### Battery Constraints        ###
# ================================ #
@constraint(m, StorageChargeFunction[τ in Timestamps], 
    StorageCharge[τ] <= AccumulatedStorageEnergyCapacity/( 4 * 4) # 4 hours of storage at 15 min intervals
)

@constraint(m, StorageDischargeFunction[τ in Timestamps], 
    StorageDischarge[τ] <= AccumulatedStorageEnergyCapacity/(4 * 4) # 4 hours of storage at 15 min intervals
)

@constraint(m, StorageLevelUpdate[t in 2:length(Timestamps)], 
    StorageLevel[Timestamps[t]] ==
        StorageLevel[Timestamps[t - 1]] * StorageLosses["Battery", "Power"] +
        StorageCharge[Timestamps[t]] * η_charge -
        StorageDischarge[Timestamps[t]] / η_discharge
)

@constraint(m, StorageLevelStartFunction[τ in Timestamps; τ==Timestamps[1]], 
    StorageLevel[τ] == 0.3*AccumulatedStorageEnergyCapacity*StorageLosses["Battery","Power"]/4 + η_charge - StorageDischarge[τ]/ η_discharge
)

@constraint(m, MaxStorageLevelFunction[τ in Timestamps], 
    StorageLevel[τ] <= AccumulatedStorageEnergyCapacity
)

# account for currently installed storage capacities
@constraint(m, StorageCapacityAccountingFunction[τ in Timestamps],
    NewStorageEnergyCapacity .== AccumulatedStorageEnergyCapacity
)

# installed capacity is limited by the maximum capacity
@constraint(m, MaxCapacityStorageFunction[τ in Timestamps],
     AccumulatedStorageEnergyCapacity <= 5000 # Maximum capacity 5 MW
)

# this starts the optimization
# the assigned solver (here HiGHS) will takes care of the solution algorithm
optimize!(m)
termination_status(m)

# ================================ #
# ✅ Print model results
using Printf

println("Installierte PV-Kapazität [kW]: ", round(value(NewSolarCapacity), digits=2))
println("Installierte Batterie-Kapazität [kWh]: ", round(value(NewStorageEnergyCapacity), digits=2))

# Sum charge/discharge energy in kWh (assuming time_step in hours, e.g. 0.25 for 15min)
total_charge = sum(value(StorageCharge[τ]) * time_step for τ in Timestamps)
total_discharge = sum(value(StorageDischarge[τ]) * time_step for τ in Timestamps)

println("Gesamte Ladeenergie [kWh]: ", round(total_charge, digits=2))
println("Gesamte Entladeenergie [kWh]: ", round(total_discharge, digits=2))

# === Extract accumulated capacities over time ===
storage_capacity_series = [value(AccumulatedStorageEnergyCapacity) for τ in Timestamps]
solar_capacity_series = [value(AccumulatedSolarCapacity) for τ in Timestamps]

# === Get the final (maximum) installed capacities ===
final_storage_capacity = round(storage_capacity_series[end], digits=2)
final_solar_capacity = round(solar_capacity_series[end], digits=2)

println("Installierte PV-Kapazität [kW]: ", final_solar_capacity)
println("Installierte Batterie-Kapazität [kWh]: ", final_storage_capacity)


# ================================ #
# --------------------
# Zeitachse
ts = collect(Timestamps)

# --------------------
# Erzeuge den Plot
# --------------------
using Plots
using Dates
using Statistics
using StatsBase  # for movmean
# Zeitachse
ts = collect(Timestamps)
ts_str = Dates.format.(ts, dateformat"yyyy-mm-dd HH:MM")

# Modell-Ergebnisse
SolarPVProductionDf         = [value(SolarPVProduction[τ]) for τ in ts]
CurtailmentDf            = [value(Curtailment[τ]) for τ in ts]
PowerPurchasedDF       = [value(PowerPurchased[τ]) for τ in ts]
Storage_DischargeDF = [value(StorageDischarge[τ]) for τ in ts]

Load_DF   = [value(LoadProfile[τ]) for τ in ts]
Storage_ChargeDF   = [value(StorageCharge[τ]) for τ in ts]
price_da         = [DayAheadPrices_Seq1[τ] for τ in ts]
price_id         = [IntradayPrices[τ] for τ in ts]

# Basisplot mit Erzeugung
# Preise skalieren
skalierungsfaktor = 1
preis_da_scaled = price_da .* skalierungsfaktor
preis_id_scaled = price_id .* skalierungsfaktor

SolarPVProductionDf = SolarPVProductionDf - CurtailmentDf


# X-Achse mit Rotation, Tick-Reduktion
import Pkg
Pkg.add("NaNStatistics")
using NaNStatistics
# X-Achse mit Rotation, Tick-Reduktion
window = 4  # 4×15min = 1h

solar_smooth     = movmean(SolarPVProductionDf, window)
net_smooth       = movmean(PowerPurchasedDF, window)
storage_dis_smooth = movmean(Storage_DischargeDF, window)
storage_cha_smooth = movmean(Storage_ChargeDF, window)
load_smooth      = movmean(Load_DF, window)
price_da_smooth  = movmean(price_da, window)
price_id_smooth  = movmean(price_id, window)


using Plots
gr()  # or plotly()

plot(
    ts_str,
    solar_smooth,
    fillrange=0,
    fillalpha=0.4,
    label="Solar PV (glatt)",
    color=:green,
    linewidth=1,
    xlabel="Zeit",
    ylabel="Leistung [kW]",
    legend=:topright,
    title="Deckung des Verbrauchs (stündlich geglättet)",
    size=(1400, 700),
    left_margin=10mm,
    right_margin=10mm,
    bottom_margin=20mm,
    guidefont=font(12),
    tickfont=font(10),
    legendfontsize=10
)

# Add the other traces
plot!(ts_str, solar_smooth .+ net_smooth, fillrange=solar_smooth,
      fillalpha=0.2, label="Netzbezug (glatt)", color=:grey, linewidth=1, yaxis=:left)

plot!(ts_str, solar_smooth .+ storage_dis_smooth, fillrange=solar_smooth,
      fillalpha=0.2, label="Speicher Entladung (glatt)", color=:blue, linewidth=1, yaxis=:left)

plot!(ts_str, load_smooth, label="Verbrauch (glatt)", color=:black, linewidth=2, yaxis=:left)

plot!(ts_str, -1 .* storage_cha_smooth, fillrange=0,
      fillalpha=0.2, label="Speicher Ladung (glatt)", color=:red, linewidth=1, yaxis=:left)

# Add right y-axis
plot!(ts_str, price_da_smooth, label="Day-Ahead Preis (glatt)",
      color=:orange, linestyle=:dash, linewidth=1.5, yaxis=:right)

plot!(ts_str, price_id_smooth, label="Intraday Preis (glatt)",
      color=:purple, linestyle=:dash, linewidth=1.5, yaxis=:right)

# Axis labels
plot!(right_ylabel="Preis [EUR/MWh]")
plot!(xrotation=30)


### ------------------------- Cost Graph ------------------------- ###
months = unique((month(τ), year(τ)) for τ in Timestamps)
println("Unique months (month, year):")
for m in sort(months, by=x -> (x[2], x[1]))  # sort by year, then month
    println(m)
end
println("Number of unique months: ", length(months))

### Netzentgelte und Stromsteuer ###
Netzentgelte_EUR_kWh = 0.15 # Netzentgelte in EUR/kWh
StromSteuer_EUR_kWh = 0.02 # Stromsteuer in EUR/kWh
Marge_EUR_kWh = 0.02 # Marge in EUR/kWh

# 1. Extract model-based cost after solving
TotalPV = value(TotalPVCost)
TotalStorage = value(TotalStorageCost)
TotalMarketPurchases = sum(value(PurchasingCost[τ]) for τ in Timestamps) 



Total_Fixed_Tariff_Cost = (1.36 + Netzentgelte_EUR_kWh + StromSteuer_EUR_kWh + Marge_EUR_kWh) * sum(LoadProfile[τ] for τ in Timestamps) * time_step # Netzentgelte in EUR/kWh
Optimized_cost = TotalPV + TotalStorage + TotalMarketPurchases

# 2. Create cost categories
labels = ["Fix-Tarif", "Spot-Tarif", "Optimiert (PV+Batterie)"]
costs = [Total_Fixed_Tariff_Cost, Spot_tariff_cost, Optimized_cost]

# Sum Revenue from Day-Ahead and Intra-Day Markets
Revenue_DayAhead = sum(value(RevenueDayAhead[τ]) for τ in Timestamps)
Revenue_IntraDay = sum(value(RevenueIntraDay[τ]) for τ in Timestamps)
Total_Revenue = Revenue_DayAhead + Revenue_IntraDay

mean(DayAheadPrices_Seq1[τ] for τ in Timestamps) # Mean Day-Ahead Price for the Spot Tariff
mean(DayAheadPrices_Seq2[τ] for τ in Timestamps) #

# 1. Labels beibehalten
labels = ["Fix-Tarif", "Spot-Tarif", "Optimiert (PV+Batterie)", "Erlöse (PV+Batterie)"]

# 2. Alle Kosten als negativ, Erlös als positiv
costs = [-Total_Fixed_Tariff_Cost, -Spot_tariff_cost, -Optimized_cost, Total_Revenue]

# 3. Einheitliche Blautöne (letzter = hellster Blauton)
farben = ["#08306b", "#2171b5", "#6baed6", "#deebf7"]  # Von sehr dunkel bis sehr hell

# 4. Bar Chart
bar(
    labels,
    costs,
    xlabel = "Tarifmodell",
    ylabel = "Gesamtkosten [EUR/Jahr]",
    legend = false,
    title = "Vergleich der jährlichen Stromkosten",
    size = (800, 500),
    bar_width = 0.5,
    color = farben
)