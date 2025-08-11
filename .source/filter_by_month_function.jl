# --- Helper function to filter by month ---
function filter_month(m::Int; y::Union{Int,Nothing}=nothing)
    idx = Dates.month.(ts_dt) .== m
    if y !== nothing
        idx .&= Dates.year.(ts_dt) .== y
    end
    return t[idx], solar_smooth[idx], net_smooth[idx], storage_dis_smooth[idx],
           load_smooth[idx], storage_cha_smooth[idx], price_da_smooth[idx], price_id_smooth[idx]
end