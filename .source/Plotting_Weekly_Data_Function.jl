using Dates
include(joinpath(data_dir, "Plotting_Function.jl"))

function plot_week(ts_dt, solar, net, dis, load, cha, da_price, id_price;
                   start::Date, days::Int=7, title::Union{Nothing,String}=nothing)
    sdt = DateTime(start)
    edt = sdt + Day(days)
    idx = (ts_dt .>= sdt) .& (ts_dt .< edt)
    @assert any(idx) "No data in selected week"

    # --- sort the input inside the window ---
    ix   = findall(idx)                          # indices in the window
    ord  = sortperm(view(ts_dt, ix))             # order by timestamp
    sel  = ix[ord]

    ord = sortperm(ts_dt)
    (ts_dt, solar, net, dis, load, cha, da_price, id_price) =
        map(a -> a[ord], (ts_dt, solar, net, dis, load, cha, da_price, id_price))

    t   = Float64.(Dates.datetime2unix.(ts_dt[idx]))
    ttl = isnothing(title) ?
        "Deckung des Verbrauchs – $(Dates.format(sdt, dateformat"dd.mm.yyyy"))–$(Dates.format(edt - Day(1), dateformat"dd.mm"))" :
        title

    return plot_stack(t, solar[idx], net[idx], dis[idx], load[idx], cha[idx],
                      da_price[idx], id_price[idx], ttl)
end

# --- 3) Weekly slicer (Monday–Sunday by start date) ---
function plot_markets_week(ts_dt, t, p_da1, p_da2, p_id, s_da1, s_da2, s_id;
                           start::Date, days::Int=7, title::Union{Nothing,String}=nothing)
    sdt = DateTime(start)
    edt = sdt + Day(days)
    idx = (ts_dt .>= sdt) .& (ts_dt .< edt)
    @assert any(idx) "No data for selected week"

    # format outside the string to avoid macro-in-string issues
    fmt_full  = dateformat"dd.mm.yyyy"
    fmt_short = dateformat"dd.mm"
    ttl_auto = string("Marktflüsse (Einkauf/Verkauf) – ",
                      Dates.format(sdt, fmt_full), "–",
                      Dates.format(edt - Day(1), fmt_short))
    ttl = isnothing(title) ? ttl_auto : title

    return plot_markets_stack(t[idx], p_da1[idx], p_da2[idx], p_id[idx],
                              s_da1[idx], s_da2[idx], s_id[idx]; title = ttl)
end