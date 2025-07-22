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


# === parameters ===
# Extract keys and values into vectors
sort(LoadProfile)
Timestamps = collect(keys(Solar_CF))

technologies = ["SolarPV"]
storages = ["Battery"]
fuels = ["Power"]

# And a Dict of maximum capacities in kW
MaxCapacity = Dict("SolarPV" => 3000, "Battery" => 5000)

η_charge = 0.95  # Efficiency of charging
η_discharge = 0.9  # Efficiency of discharging


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
@objective(m, Max, 
#   sum(RevenueDayAhead[τ] for τ in Timestamps)  # Profits from Trading Day Ahead
#  + sum(RevenueIntraDay[τ] for τ in Timestamps)  # Profits from Intra-Day Trading
    - TotalPVCost
    - TotalStorageCost
    - sum(PurchasingCost[τ] for τ in Timestamps)
)

### Profit and Loss Accounting
### Investment Kosten in EUR/KWh
@constraint(m, ProductionCostFunction,
    sum(SolarPVProduction[τ] * 0.01/4 for τ in Timestamps) + 750/5  * 120/8760 * NewSolarCapacity == TotalPVCost
)

# Battery Cost, 250 EUR per kWh with 15 years of lifetime
@constraint(m, StorageCostFunction, 
    TotalStorageCost == NewStorageEnergyCapacity * 250/5 * 120/8760)

# Day-Ahead Market Cost Function
# Einnahmen in EUR/KWh
@constraint(m, PurchasingCostFunction[τ in Timestamps],
    PurchasingCost[τ] == PurchasedDayAhead_Seq1[τ] * DayAheadPrices_Seq1[τ] / 1000 + 
                        PurchasedDayAhead_Seq2[τ] * DayAheadPrices_Seq2[τ] / 1000
                        + (PurchasedDayAhead_Seq1[τ] + PurchasedDayAhead_Seq2[τ]) 
                        * (Netzentgelte_EUR_kWh + StromSteuer_EUR_kWh + Marge_EUR_kWh)
)

# Day-Ahead Revenue Function
@constraint(m, SalesFunction[τ in Timestamps],
    RevenueDayAhead[τ] == SellingDayAhead_Seq1[τ] * DayAheadPrices_Seq1[τ] / 1000 # Converting EUR/MWh to EUR/kWh
                        + SellingDayAhead_Seq2[τ] * DayAheadPrices_Seq2[τ] / 1000 # Converting EUR/MWh to EUR/kWh
)
# Intraday Market Revenue Function
@constraint(m, SalesFunctionIntraDay[τ in Timestamps],
    RevenueIntraDay[τ] ==
        SellingIntraDay[τ] * IntradayPrices[τ] / 1000  # Converting EUR/MWh to EUR/kWh
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


value.(AccumulatedStorageEnergyCapacity)
value.(AccumulatedSolarCapacity)
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

p = plot(
    ts_str,
    SolarPVProductionDf,
    fillrange=0,
    fillalpha=0.4,
    label="Solar PV",
    color=:green,
    linewidth=0,
    xlabel="Zeit",
    ylabel="Leistung [kW]",
    legend=:topright,
    title="Deckung des Verbrauchs"
)

# Netzbezug
plot!(ts_str, SolarPVProductionDf .+ PowerPurchasedDF, fillrange=SolarPVProductionDf,
      fillalpha=0.3, label="Netzbezug", color=:grey, linewidth=0.5)

# Add Speicher Entladung stacked on top of Solar PV
plot!(ts_str, SolarPVProductionDf .+ Storage_DischargeDF, fillrange=SolarPVProductionDf,
    fillalpha=0.3, label="Speicher Entladung", color=:blue,linewidth=0
)

# Verbrauch als Linie (dunkelgrau, gestrichelt)
plot!(ts_str, load_DF, label="Verbrauch", color=:black, linewidth=1)

# Speicherladung unten (negative Nachfrage)
plot!(ts_str, -1 .* Storage_ChargeDF, fillrange=0, fillalpha=0.3, label="Speicher Ladung", color=:red, linewidth=0)



# Börsenpreise als Linien
plot!(ts_str, preis_da_scaled, label="Day-Ahead Preis (skaliert)", color=:black, linewidth=1.5)
plot!(ts_str, preis_id_scaled, label="Intraday Preis (skaliert)", color=:orange, linewidth=1.5)

# X-Achse mit Rotation, Tick-Reduktion
xticks = 1:96:length(ts)
plot!(xticks=xticks, xrotation=30)

