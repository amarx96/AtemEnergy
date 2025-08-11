"""
    annualized_solar_cost(capex, lifetime, wacc)

Calculate the annualized investment cost for a Solar PV system.

# Arguments
- `capex`: Investment cost [€/kW]
- `lifetime`: Technical/economic lifetime [years]
- `wacc`: Weighted Average Cost of Capital (decimal, e.g. 0.05 for 5%)

# Returns
- Annualized cost [€/kW/year]
"""
function annualized_solar_cost_function(capex::Float64, lifetime::Int, wacc::Float64)
    crf = (wacc * (1 + wacc)^lifetime) / ((1 + wacc)^lifetime - 1) # Capital Recovery Factor
    return capex * crf
end


function annuity_factor(r::Float64, n::Int)
    return (r * (1 + r)^n) / ((1 + r)^n - 1)
end