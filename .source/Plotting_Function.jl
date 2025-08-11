using Dates, Colors, CairoMakie
CairoMakie.activate!()

function plot_stack(t, solar, net, dis, load, cha, da_price, id_price, title_str)
    # --- 1) sort by time (only arguments; no globals)
    ord       = sortperm(t)
    t         = t[ord]
    solar     = solar[ord]
    net       = net[ord]
    dis       = dis[ord]
    load      = load[ord]
    cha       = cha[ord]
    da_price  = da_price[ord]
    id_price  = id_price[ord]

    # --- 2) left axis (power)
    fig = Figure(size = (1400, 700), padding = 20)
    ax = Axis(fig[1, 1];
        xlabel = "Zeit", ylabel = "Leistung [kW]", title = title_str,
        xtickformat = xs -> Dates.format.(Dates.unix2datetime.(round.(Int, xs)),
                                          dateformat"dd.mm. HH:MM"),
    )

    # nonnegative layers & clipping to load
    solar = max.(solar, 0.0); dis = max.(dis, 0.0); net = max.(net, 0.0)
    s0 = zeros(length(load))
    s1 = clamp.(solar, 0, load)
    s2 = clamp.(s1 .+ dis, 0, load)
    s3 = clamp.(s2 .+ net, 0, load)

    band!(ax, t, s0, s1; color = (:green, 0.35), label = "Solar PV (glatt)")
    band!(ax, t, s1, s2; color = (:blue,  0.25), label = "Speicher Entladung (glatt)")
    band!(ax, t, s2, s3; color = (:gray,  0.25), label = "Netzbezug (glatt)")
    band!(ax, t, -max.(cha, 0.0), s0; color = (:red, 0.25), label = "Speicher Ladung (glatt)")
    lines!(ax, t, load; color = :black, linewidth = 1.2, label = "Verbrauch (glatt)")

    # --- 3) right axis (prices, log scale)
    # shift if needed so all values > 0
    minp = min(minimum(da_price), minimum(id_price))
    shift = minp <= 0 ? (1.0 - minp) : 0.0
    p_da = da_price .+ shift
    p_id = id_price .+ shift

    ax_r = Axis(fig[1, 1]; yscale = log10)   # log-scale right axis
    ax_r.yaxisposition[] = :right
    hidexdecorations!(ax_r, grid = false)
    ax_r.ylabel[] = shift == 0 ?
        "Preis [EUR/MWh] (log)" :
        "Preis [EUR/MWh] (log; +$(round(shift,digits=2)))"
    ax_r.yticklabelcolor[] = colorant"orange"
    linkxaxes!(ax, ax_r)

    lines!(ax_r, t, p_da; color = :orange, linewidth = 1.0, linestyle = :dash,
           label = "Day-Ahead Preis")
    lines!(ax_r, t, p_id; color = :purple, linewidth = 1.0, linestyle = :dash,
           label = "Intraday Preis")

    axislegend(ax,  position = :rt)
    axislegend(ax_r, position = :rb, tellwidth = false, tellheight = false)
    ax.xticklabelrotation = π/6
    fig
end