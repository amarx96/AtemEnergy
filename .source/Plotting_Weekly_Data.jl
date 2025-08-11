function plot_week(ts_dt, solar, net, dis, load, cha, da_price, id_price;
                   start::Date, days::Int=7, title::Union{Nothing,String}=nothing)

    sdt = DateTime(start)
    edt = sdt + Day(days)
    idx = (ts_dt .>= sdt) .& (ts_dt .< edt)
    @assert any(idx) "No data in selected week"

    # numeric timestamps for plotting
    t = Float64.(Dates.datetime2unix.(ts_dt[idx]))

    ttl = isnothing(title) ?
        "Deckung des Verbrauchs – $(Dates.format(sdt, dateformat"dd.mm.yyyy"))–$(Dates.format(edt - Day(1), dateformat"dd.mm"))" :
        title

    return plot_stack(t, solar[idx], net[idx], dis[idx], load[idx], cha[idx],
                      da_price[idx], id_price[idx], ttl)
end