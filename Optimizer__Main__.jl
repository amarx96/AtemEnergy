# Main Battery Optimizer
const data_dir = abspath(joinpath(@__DIR__, ".source"))
isdir(data_dir) || mkpath(data_dir)




### Import dependencies
include(joinpath(data_dir, "install_and_import.jl")) # Install and import required packages
include(joinpath(data_dir, "Import_CapacityFactor.jl"))
include(joinpath(data_dir, "Import_PriceData.jl"))
include(joinpath(data_dir, "Import_Lastprofil.jl"))
include(joinpath(data_dir, "Import_Lastprofil.jl")) # Import Load Profile
include(joinpath(data_dir, "annualized_capex.jl")) # Import Price Data
include(joinpath(data_dir, "filter_by_month_function.jl"))
include(joinpath(data_dir, "Plotting_Function.jl"))
include(joinpath(data_dir, "Plotting_Weekly_Data_Function.jl"))
include(joinpath(data_dir, "GridFees_Function.jl"))

# ========================= #
### Fix Input Parameters ###
# ========================= #
time_step = 15 / 60 # Time step in minutes

sort(LoadProfile)
Timestamps = collect(keys(LoadProfile))
sort!(Timestamps)

all15 = collect(minimum(Timestamps):Minute(15):maximum(Timestamps))
Price_Seq_1 = copy(DayAheadPrices_Seq1)
Price_Seq_2 = copy(DayAheadPrices_Seq2)
for t in all15
    if !haskey(Price_Seq_1, t)
        # forward-fill (simple & robust)
        prev = t - Minute(15)
        while !haskey(Price_Seq_1, prev); prev -= Minute(15); end
        Price_Seq_1[t] = Price_Seq_1[prev]
    end
end
for t in all15
    if !haskey(Price_Seq_2, t)
        # forward-fill (simple & robust)
        prev = t - Minute(15)
        while !haskey(Price_Seq_2, prev); prev -= Minute(15); end
        Price_Seq_2[t] = Price_Seq_2[prev]
    end
end

# Create a dictionary for Intra-Day Prices
IntradayPrices_Intrapolate = copy(IntradayPrices)
for t in all15
    if !haskey(IntradayPrices_Intrapolate, t)
        # forward-fill (simple & robust)
        prev = t - Minute(15)
        while !haskey(IntradayPrices_Intrapolate, prev); prev -= Minute(15); end
        IntradayPrices_Intrapolate[t] = IntradayPrices_Intrapolate[prev]
    end
end

# Create a dictionary for Intra-Day Prices
IntradayPrices_Intrapolate = copy(IntradayPrices)
for t in all15
    if !haskey(IntradayPrices_Intrapolate, t)
        # forward-fill (simple & robust)
        prev = t - Minute(15)
        while !haskey(IntradayPrices_Intrapolate, prev); prev -= Minute(15); end
        IntradayPrices_Intrapolate[t] = IntradayPrices_Intrapolate[prev]
    end
end

# Create a dictionary for Intra-Day Prices
LoadProfile_Intrapolate = copy(LoadProfile)
for t in all15
    if !haskey(LoadProfile_Intrapolate, t)
        # forward-fill (simple & robust)
        prev = t - Minute(15)
        while !haskey(LoadProfile_Intrapolate, prev); prev -= Minute(15); end
        LoadProfile_Intrapolate[t] = LoadProfile_Intrapolate[prev]
    end
end


# Interpolate Solar Capacity Factor
Solar_CF_Intrapolate = copy(Solar_CF)
for t in all15
    if !haskey(Solar_CF_Intrapolate, t)
        # forward-fill (simple & robust)
        prev = t - Minute(15)
        while !haskey(Solar_CF_Intrapolate, prev); prev -= Minute(15); end
        Solar_CF_Intrapolate[t] = Solar_CF_Intrapolate[prev]
    end
end

# ========================== #
# == Site Specific Data   == #
# ========================== #
# And a Dict of maximum capacities in kW
MaxSolarCapacity = 5000 # in kW
MaxBatteryCapacity = 5000  # in kWh

# Maximum Netzanschluss leistung
MaxGridConnection = maximum(values(LoadProfile_Intrapolate))


# ========================== #
# == Solar PV Data        == #
# ========================== #
InstalledSolarCapacity = 5000.0  # in kW
MaxSolarCapacity = 8000.0   # in kW

# Inputs
pv_capex = 700.0          # €/kW  (your value)
wacc_pv  = 0.05           # -
life_pv  = 25             # years

pv_om_frac = 0.015        # 1.5% of CAPEX per year  (use 0.01..0.02 as sensitivity)
pv_var_om_eur_per_kwh = 0.0

pv_inv_rep_frac = 0.12    # 12% of CAPEX
pv_inv_life     = 12      # years


# ================================
# Battery Technology Parameters
# Source: TU Berlin lecture slide
# ================================
# Capture Rate of high Prices
capture_rate = 0.85  # 85% of high prices captured
Max_Battery_Capacity = 5000  # in kWh

# Li-ion Battery Parameters
li_ion = Dict(
    :charge_efficiency => 0.97,               # [%]
    :discharge_efficiency => 0.97,            # [%]
    :max_DOD => 0.90,                         # [%]
    :capacity_cost => 250.0,                  # [€/kWh] - storage only
    :BMS_cost => 30.0,                        # [€/kWh]
    :converter_cost => 100.0,                 # [€/kW]
    :max_cycles => 5000,                      # [-]
    :calendar_life => 15,                     # [years]
    :self_discharge_per_day => 0.005,         # [%/day] → 0.5% = 0.005
    :repair_maintenance_cost => 0.01          # [%/year] → 1% = 0.01
)

# Lead-acid Battery Parameters
lead_acid = Dict(
    :charge_efficiency => 0.99,
    :discharge_efficiency => 0.94,
    :max_DOD => 0.80,
    :capacity_cost => 100.0,
    :BMS_cost => 10.0,
    :converter_cost => 100.0,
    :max_cycles => 1500,
    :calendar_life => 10,
    :self_discharge_per_day => 0.003,
    :repair_maintenance_cost => 0.01
)

# Converter Costs
const C_LEVELS = [0.5, 1.0, 2.0, 4.0]                 # C [1/h]
const CONV_COST = Dict(                              # €/kW converter
    0.5 => 70.0,
    1.0 => 100.0,
    2.0 => 140.0,
    4.0 => 220.0,
)


const r_disc      = 0.05                       # Discount Rate
const DoD_max     = li_ion[:max_DOD]           # e.g. 0.90
const Cycles_max  = li_ion[:max_cycles]        # e.g. 5000
const Cal_years   = li_ion[:calendar_life]     # e.g. 15
const OM_frac     = li_ion[:repair_maintenance_cost]  # e.g. 0.01
const η_charge   = li_ion[:charge_efficiency]    
const η_discharge = li_ion[:discharge_efficiency] 

isdefined(@__MODULE__, :C_RATE) || (const C_RATE = 0.5)

const battery_capex = li_ion[:capacity_cost] + li_ion[:BMS_cost]
const conv_capex = li_ion[:converter_cost]
const SelfDischargeLosses = li_ion[:self_discharge_per_day] 
const Δh = 15/60                  # hours
const soc0 = 0.30                 # initial SoC fraction
const keep = (1 - SelfDischargeLosses)^(Δh/24)  # per-step keep factor




# ========================== #
# == Energy Market Data   == #
# ========================== #
### Netzentgelte und Stromsteuer ###
Netzentgelte_EUR_kWh = 0.15 # Netzentgelte in EUR/kWh
StromSteuer_EUR_kWh = 0.02 # Stromsteuer in EUR/kWh
Marge_EUR_kWh = 0.02 # Marge in EUR/kWh

# ========================== #
# == Building the Model   == #
# ========================== #
ENV["GRB_LICENSE_FILE"]           # should print the same path
using JuMP, Gurobi
const GRB_ENV = Gurobi.Env()      # must be created AFTER setting the env var
m = Model(() -> Gurobi.Optimizer(GRB_ENV))  # replace your HiGHS line


# PV Data
@variable(m, TotalCostSolarPV>= 0)
@variable(m, SolarPVProduction[Timestamps] >= 0)
@variable(m, NewSolarCapacity>=0)
@variable(m, AccumulatedSolarCapacity >=0)
@variable(m, Curtailment[Timestamps] >=0)

### And we also need to add our new variables for storages
@variable(m, NewStorageEnergyCapacity>=0)
@variable(m, AccumulatedStorageEnergyCapacity>=0)
@variable(m, NewStoragePowerCapacity>=0)
@variable(m, AccumulatedStoragePowerCapacity>=0)
@variable(m, StorageCharge[Timestamps]>=0)
@variable(m, StorageDischarge[Timestamps]>=0)
@variable(m, StorageLevel[Timestamps]>=0)
@variable(m, TotalStorageCost >= 0)

# Add Market variables
@variable(m, MaxTariff[Timestamps] >= 0)
@variable(m, PowerPurchasedDA[Timestamps] >= 0)
@variable(m, PurchasedIDA[Timestamps] >= 0)

@variable(m, PurchasedDayAhead[fuels, Timestamps] >= 0)
@variable(m, PurchasedDayAhead_Seq1[Timestamps] >= 0)
@variable(m, PurchasedDayAhead_Seq2[Timestamps] >= 0)

# Selling Variables
# Day-Ahead Market 
@variable(m, SellingDayAhead_Seq1[Timestamps] >= 0)
@variable(m, SellingDayAhead_Seq2[Timestamps] >= 0)

# Intra-Day Market
@variable(m, SellingIntraDay[Timestamps] >= 0)


# Netz Variablen

# =============================================== #
###         Formulating the Model               ###
# =============================================== #
# ============================== #
# Purchasing Cost Cost Function
# ============================== #
# then use `Price_Seq_1` in your constraints
@constraint(m, [τ in Timestamps], MaxTariff[τ] >= Price_Seq_1[τ])
@constraint(m, [τ in Timestamps], MaxTariff[τ] >= Price_Seq_2[τ])

# Import = DA1 + DA2 + IDA (if ID should count towards peak/costs)
@expression(m, PowerPurchased[τ in Timestamps],
    PurchasedDayAhead_Seq1[τ] + PurchasedDayAhead_Seq2[τ] + PurchasedIDA[τ]
)

# Kosten Stromeinkauf in EUR/KWh
# Per-timestep purchasing cost in EUR
@expression(m, PurchasingCost[τ in Timestamps],
        ( PurchasedDayAhead_Seq1[τ] * (Price_Seq_1[τ]/1000)
        + PurchasedDayAhead_Seq2[τ] * (Price_Seq_2[τ]/1000)
        + PurchasedIDA[τ] * (IntradayPrices_Intrapolate[τ] / 1000)) * time_step * (1 + (1-capture_rate))
        + PowerPurchased[τ] * (Netzentgelte_EUR_kWh + StromSteuer_EUR_kWh + Marge_EUR_kWh) * time_step
)


# Kosten Spitzenlast in EUR/kW
# ---- Monatsleistungspreis (€/Monat) ----
# helper + index sets
month_key(τ) = (year(τ), month(τ))
month_keys   = sort(unique(month_key.(Timestamps)))
days_in_month = Dict(k => daysinmonth(Date(k[1], k[2], 1)) for k in month_keys)

@variable(m, PeakImport[(yy, mm) in month_keys] >= 0)
@constraint(m, PeakDef[τ in Timestamps],
    PowerPurchased[τ]  <= PeakImport[month_key(τ)]
)

@expression(m, LeistungsBezugsKosten,
    sum(col(LP_EUR_kW_mon[days_in_month[k]]) * PeakImport[k] for k in month_keys )
)

# Day-Ahead Revenue Function
@expression(m, RevenueDayAhead[τ in Timestamps],
                        (SellingDayAhead_Seq1[τ] * Price_Seq_1[τ] / 1000 # Converting EUR/MWh to EUR/kWh
                        + SellingDayAhead_Seq2[τ] * Price_Seq_2[τ] / 1000) # Converting EUR/MWh to EUR/kWh
                        * time_step * capture_rate
)

# Intraday Market Revenue Function
@expression(m, RevenueIntraDay[τ in Timestamps],
        SellingIntraDay[τ] * IntradayPrices_Intrapolate[τ] / 1000 * time_step * capture_rate # Converting EUR/MWh to EUR/kWh
)


# ================================ #
### Technical Constraints        ###
# ================================ #
@expression(m, PowerSold[τ in Timestamps],
    SellingIntraDay[τ] + SellingDayAhead_Seq1[τ] + SellingDayAhead_Seq2[τ]
)

### Energy Balance Constraints ###
@constraint(m, Massenbilanz2[τ in Timestamps],
   SolarPVProduction[τ]  
    + StorageDischarge[τ]
    + PowerPurchased[τ]
    ==
    StorageCharge[τ]
    + LoadProfile_Intrapolate[τ]
    + Curtailment[τ]
    + PowerSold[τ]
)


@constraint(m, MaxGridConnectionFunction[τ in Timestamps],
     PowerSold[τ] + PowerPurchased[τ] <= MaxGridConnection # Maximum grid connection capacity
)

# ================================ #
### Solar PV Constraints        ###
# ================================ #
# Annualized CAPEX for modules+BOS
@expression(m, PV_Annuity,
    pv_capex * annuity_factor(wacc_pv, life_pv) * NewSolarCapacity
)

# Fixed O&M as % of CAPEX (€/yr)
@expression(m, PV_OM_fixed,
    pv_om_frac * pv_capex * NewSolarCapacity
)

# Optional variable O&M (€/yr)
@expression(m, PV_OM_var,
    pv_var_om_eur_per_kwh * sum(SolarPVProduction[τ] * time_step for τ in Timestamps)
)

# Inverter replacement annualized (€/yr)
@expression(m, PV_Inverter_Annuity,
    pv_inv_rep_frac * pv_capex * annuity_factor(wacc_pv, pv_inv_life) * NewSolarCapacity
)

# Total PV cost per year (put this in your objective with a minus sign)
@expression(m, TotalPVCost,
    PV_Annuity + PV_OM_fixed + PV_Inverter_Annuity + PV_OM_var
)

# for variable renewables, the production needs to be always at maximum
@constraint(m, ProductionFunction_res[τ in Timestamps],
    AccumulatedSolarCapacity * Solar_CF_Intrapolate[τ] / time_step ==  SolarPVProduction[τ]
)

# installed capacity is limited by the maximum capacity
@constraint(m, MaxSolarCapacityFunction,
     AccumulatedSolarCapacity <= MaxSolarCapacity # Maximum capacity 5 MW
)

# calculate the total installed capacity in each year
@constraint(m, CapacityAccountingFunction,
    NewSolarCapacity == AccumulatedSolarCapacity)

@constraint(m, InstalledSolarCapacityConstraint, 
    InstalledSolarCapacity <= AccumulatedSolarCapacity# in kW
)

#==============================================#
# === Battery cost components (all linear) === #
#==============================================#
@expression(m, Annual_Discharge_Throughput,  # kWh at battery DC over the horizon
    sum(StorageDischarge[τ] * time_step / η_discharge for τ in Timestamps)
)

@expression(m, Batt_Annuity_Calendar,        # EUR/year
    (NewStorageEnergyCapacity * (battery_capex + conv_capex * C_RATE) * annuity_factor(r_disc, Cal_years))
    )

@expression(m, Batt_Annuity_Throughput,      # EUR/year
    ((battery_capex + conv_capex * C_RATE) / (Cycles_max * DoD_max)) * Annual_Discharge_Throughput
)

@expression(m, Batt_OM,                      # simple % O&M on installed capex (EUR/year)
    OM_frac * NewStorageEnergyCapacity * battery_capex
)



# Enforce TotalStorageCost to cover the binding driver + O&M
@constraint(m, StorageCost_calendar_lb,   TotalStorageCost >= Batt_Annuity_Calendar + Batt_OM)
@constraint(m, StorageCost_throughput_lb, TotalStorageCost >= Batt_Annuity_Throughput + Batt_OM)

# =========================================== #
# Storage Energy Constraints
# =========================================== #
@constraint(m, StorageLevelStartFunction[τ in Timestamps; τ==Timestamps[1]], 
    StorageLevel[τ] == 0.5*AccumulatedStorageEnergyCapacity
)

@constraint(m, SoC_min[τ in Timestamps],
    StorageLevel[τ] >= (1 - DoD_max) * AccumulatedStorageEnergyCapacity)

@constraint(m, SoC_max[τ in Timestamps],
    StorageLevel[τ] <= AccumulatedStorageEnergyCapacity)

# account for currently installed storage capacities
@constraint(m, StorageCapacityAccountingFunction,
    NewStorageEnergyCapacity == AccumulatedStorageEnergyCapacity
)

# installed capacity is limited by the maximum capacity
@constraint(m, MaxCapacityStorageFunction,
     AccumulatedStorageEnergyCapacity <= Max_Battery_Capacity # Maximum capacity 5 MWh
)

# =========================================== #
# Storage Power Constraints
# =========================================== #
# Power limits
@constraint(m, [τ in Timestamps], StorageCharge[τ]    <= C_RATE * AccumulatedStorageEnergyCapacity)
@constraint(m, [τ in Timestamps], StorageDischarge[τ] <= C_RATE * AccumulatedStorageEnergyCapacity)



@variable(m, z[Timestamps], Bin)
M = 1e3
@constraint(m, [τ in Timestamps], StorageCharge[τ]    <= M*z[τ])
@constraint(m, [τ in Timestamps], StorageDischarge[τ] <= M*(1 - z[τ]))


# State of Charge
@constraint(m, StorageLevelUpdate[t in 2:length(Timestamps)],
    StorageLevel[Timestamps[t]] ==
        keep * StorageLevel[Timestamps[t-1]] +
        η_charge       * StorageCharge[Timestamps[t]]   * Δh -
        (1/η_discharge)* StorageDischarge[Timestamps[t]]* Δh
)


# ================================ #
### Implement Objective Function ###
# ================================ #
# Maximizing the difference between cost of Battery + PV and Sport-Tariff Procurement
@objective(m, Max, 
   sum(RevenueDayAhead[τ] for τ in Timestamps)  # Profits from Trading Day Ahead
  + sum(RevenueIntraDay[τ] for τ in Timestamps)  # Profits from Intra-Day Trading
  + sum(PowerSold[τ] * Netzentgelte_EUR_kWh * time_step for τ in Timestamps)  # Rückerstattung der Netznutzungsnetgelte
    - TotalPVCost
    - TotalStorageCost
    - LeistungsBezugsKosten
    - sum(PurchasingCost[τ] for τ in Timestamps))


# this starts the optimization
# the assigned solver (here HiGHS) will takes care of the solution algorithm
optimize!(m)
termination_status(m)


# ================================ #
### Export Model Results         ### 
# ================================ #
# Modell-Ergebnisse
SolarPVProductionDf         = [value(SolarPVProduction[τ]) for τ in Timestamps]
CurtailmentDf            = [value(Curtailment[τ]) for τ in Timestamps]
PowerPurchasedDF       = [value(PowerPurchased[τ]) for τ in Timestamps]
Storage_DischargeDF = [value(StorageDischarge[τ]) for τ in Timestamps]

Load_DF   = [value(LoadProfile[τ]) for τ in Timestamps]
Storage_ChargeDF   = [value(StorageCharge[τ]) for τ in Timestamps]
price_da         = [Price_Seq_1[τ] for τ in Timestamps]
price_id         = [IntradayPrices_Intrapolate[τ] for τ in Timestamps]

# ✅ Print model results
using Printf

println("Installierte PV-Kapazität [kW]: ", round(value(NewSolarCapacity), digits=0))
println("Installierte Batterie-Kapazität [kWh]: ", round(value(NewStorageEnergyCapacity), digits=0))

# Sum charge/discharge energy in kWh (assuming time_step in hours, e.g. 0.25 for 15min)
total_charge = round(sum(value(StorageCharge[τ]) * time_step for τ in Timestamps),digits=0)
total_discharge = round(sum(value(StorageDischarge[τ]) * time_step for τ in Timestamps),digits=0)

println("Gesamte Ladeenergie [kWh]: ", round(total_charge, digits=2))
println("Gesamte Entladeenergie [kWh]: ", round(total_discharge, digits=2))

# === Extract accumulated capacities over time ===
storage_capacity_series = [value(AccumulatedStorageEnergyCapacity) for τ in Timestamps]
solar_capacity_series = [value(AccumulatedSolarCapacity) for τ in Timestamps]

# === Get the final (maximum) installed capacities ===
final_storage_capacity = round(storage_capacity_series[end], digits=0)
final_solar_capacity = round(solar_capacity_series[end], digits=0)

println("Installierte PV-Kapazität [kW]: ", final_solar_capacity)
println("Installierte Batterie-Kapazität [kWh]: ", final_storage_capacity)

# =========================================== #
###              Visualisierung             ###
# =========================================== #
include(joinpath(@__DIR__,"Plotting_Function.jl"))
include(joinpath(@__DIR__,"Plotting_Weekly_Data_Function.jl"))

ts_dt = Timestamps  # use your timestamps as-is (Date/DateTime/String vectors all work)
t = Dates.datetime2unix.(ts_dt)  # Vector{Float64}

### Adjust Price Data
skalierungsfaktor = 1
preis_da_scaled = price_da .* skalierungsfaktor
preis_id_scaled = price_id .* skalierungsfaktor

SolarPVProductionDf = SolarPVProductionDf - CurtailmentDf

window = 4  # 96 * 15 minutes = 24 hours
# Smoothing the Data
solar_smooth     = movmean(SolarPVProductionDf, window)
net_smooth       = movmean(PowerPurchasedDF, window)
storage_dis_smooth = movmean(Storage_DischargeDF, window)
storage_cha_smooth = movmean(Storage_ChargeDF, window)
load_smooth      = movmean(Load_DF, window)
price_da_smooth  = movmean(price_da, window)
price_id_smooth  = movmean(price_id, window)


# Sort everything according to the timestamps
order = sortperm(ts_dt)
t = t[order]
solar_smooth        = solar_smooth[order]
net_smooth          = net_smooth[order]
storage_dis_smooth  = storage_dis_smooth[order]
load_smooth         = load_smooth[order]
storage_cha_smooth  = storage_cha_smooth[order]
price_da_smooth     = price_da_smooth[order]
price_id_smooth     = price_id_smooth[order]

# =========================================== #
###              Monthly                     ###
# =========================================== #

# Get January and July subsets
t_jan, solar_jan, net_jan, dis_jan, load_jan, cha_jan, da_jan, id_jan = filter_month(1)
t_jul, solar_jul, net_jul, dis_jul, load_jul, cha_jul, da_jul, id_jul = filter_month(7)


# --- Create and display the figures for Monthly Data ---
fig_jan = plot_stack(t_jan, solar_jan, net_jan, dis_jan, load_jan, cha_jan, da_jan, id_jan,
                     "Deckung des Verbrauchs – Januar")

fig_jul = plot_stack(t_jul, solar_jul, net_jul, dis_jul, load_jul, cha_jul, da_jul, id_jul,
                     "Deckung des Verbrauchs – Juli")

display(fig_jan)
display(fig_jul)

save("C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Ergebnisse\\DX_Center\\verbrauch_jan.png", fig_jan)
save("C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Ergebnisse\\DX_Center\\verbrauch_jul.png", fig_jul)

# =========================================== #
###              Weekly                     ###
# =========================================== #

include(joinpath(@__DIR__,"Plotting_Weekly_Data_Function.jl"))
# Week 2 of January and July (adjust year as needed)
# plot_week(ts_dt, solar, net, dis, load, cha, da_price, id_price)

ts_dt, solar, net, dis, load, cha, da_price, id_price

fig_jan_w2 = plot_week(ts_dt,
    solar_smooth, net_smooth, storage_dis_smooth,
    load_smooth,               # ✅ load
    storage_cha_smooth,        # ✅ charge
    price_da_smooth, price_id_smooth;
    start = Date(2024, 1, 8))

fig_jul_w2 = plot_week(ts_dt, solar_smooth, net_smooth, storage_dis_smooth,
                       load_smooth, storage_cha_smooth, price_da_smooth, price_id_smooth;
                       start = Date(2024, 7, 8))

display(fig_jan_w2)
display(fig_jul_w2)
# save("week_jan_w2.png", fig_jan_w2); save("week_jul_w2.png", fig_jul_w2)
save("C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Ergebnisse\\DX_Center\\week_jan_w2.png", fig_jan_w2)
save("C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Ergebnisse\\DX_Center\\week_jul_w2.png", fig_jul_w2)


# =========================================== #
###             Trading Monthly              ###
# =========================================== #
include(joinpath(@__DIR__, "Trading_Plots_Function.jl"))
# --- 0) Pull and smooth flows (same window you already use) ---
p_da1 = [value(PurchasedDayAhead_Seq1[τ]) for τ in Timestamps]
p_da2 = [value(PurchasedDayAhead_Seq2[τ]) for τ in Timestamps]
p_id  = [value(PurchasedIDA[τ])            for τ in Timestamps]

s_da1 = [value(SellingDayAhead_Seq1[τ])    for τ in Timestamps]
s_da2 = [value(SellingDayAhead_Seq2[τ])    for τ in Timestamps]
s_id  = [value(SellingIntraDay[τ])         for τ in Timestamps]

window = 4  # same smoothing as before
p_da1_s = movmean(p_da1, window); p_da2_s = movmean(p_da2, window); p_id_s  = movmean(p_id, window)
s_da1_s = movmean(s_da1, window); s_da2_s = movmean(s_da2, window); s_id_s  = movmean(s_id, window)

# Sort by time once
ord = sortperm(Timestamps)
ts_dt = Timestamps[ord]
t = Float64.(Dates.datetime2unix.(ts_dt))
p_da1_s, p_da2_s, p_id_s = p_da1_s[ord], p_da2_s[ord], p_id_s[ord]
s_da1_s, s_da2_s, s_id_s = s_da1_s[ord], s_da2_s[ord], s_id_s[ord]



# --- 4) Create figures ---

# Monthly examples
fig_mkt_jan = plot_markets_month(ts_dt, t, p_da1_s, p_da2_s, p_id_s, s_da1_s, s_da2_s, s_id_s; mon=1, yr=2024)
fig_mkt_jul = plot_markets_month(ts_dt, t, p_da1_s, p_da2_s, p_id_s, s_da1_s, s_da2_s, s_id_s; mon=7, yr=2024)

display(fig_mkt_jan)
display(fig_mkt_jul)

# Weekly examples (week starting on the given date)
fig_mkt_jan_w2 = plot_markets_week(ts_dt, t, p_da1_s, p_da2_s, p_id_s, s_da1_s, s_da2_s, s_id_s; start=Date(2024,1,8))
fig_mkt_jul_w2 = plot_markets_week(ts_dt, t, p_da1_s, p_da2_s, p_id_s, s_da1_s, s_da2_s, s_id_s; start=Date(2024,7,8))

display(fig_mkt_jan_w2)
display(fig_mkt_jul_w2)

# optional: save
save("C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Ergebnisse\\DX_Center\\markt_jan.png",    fig_mkt_jan)
save("C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Ergebnisse\\DX_Center\\markt_jul.png",    fig_mkt_jul)
save("C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Ergebnisse\\DX_Center\\markt_jan_w2.png", fig_mkt_jan_w2)
save("C:\\Users\\alex-\\Desktop\\BatteryStorage\\Optimization\\Ergebnisse\\DX_Center\\markt_jul_w2.png", fig_mkt_jul_w2)