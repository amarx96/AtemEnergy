# --- 1) Core stack plot used by both month/week ---

# helper that actually draws and sets safe limits
function plot_markets_stack(t, p_da1, p_da2, p_id, s_da1, s_da2, s_id; title::AbstractString)
    n  = length(t)
    fig = Figure(size = (1600, 800), padding = 28)
    ax  = Axis(fig[1, 1];
        xlabel = "Zeit", ylabel = "Leistung [kW]", title = title,
        xtickformat = xs -> Dates.format.(Dates.unix2datetime.(round.(Int, xs)),
                                          dateformat"dd.mm. HH:MM")
    )



    # add a healthy padding: at least 50 kW or 12% of range
    pad = max(0.12 * (yrng > 0 ? yrng : 1.0), 50.0)

    # Einkauf (positive)
    band!(ax, t, zeros(n), p_da1; color = (:steelblue, 1), label = "Einkauf DA Seq1")
    band!(ax, t, zeros(n), p_da2; color = (:steelblue, 0.75), label = "Einkauf DA Seq2")
    band!(ax, t, zeros(n), p_id;  color = (:steelblue, 0.45), label = "Einkauf Intraday")

    # Verkauf (negative)
    band!(ax, t, -s_da1, zeros(n); color = (:tomato, 1), label = "Verkauf DA Seq1")
    band!(ax, t, -s_da2, zeros(n); color = (:tomato, 0.75), label = "Verkauf DA Seq2")
    band!(ax, t, -s_id,  zeros(n); color = (:tomato, 0.45), label = "Verkauf Intraday")



    # ---- generous y-limits so nothing touches the frame ----
    # consider only finite values
    all_pos = max.(0, max.(max.(p_da1, p_da2), p_id))           # purchases (>= 0)
    all_neg = min.(0, -max.(max.(s_da1, s_da2), s_id))          # sales as negative

    ymin = minimum(all_neg)
    ymax = maximum(all_pos)
    yrng = ymax - ymin

    # add a healthy padding: at least 50 kW or 12% of range
    pad = max(0.12 * (yrng > 0 ? yrng : 1.0), 50.0)

    # set limits after all series are added
    ylims!(ax, ymin - pad, ymax + pad)
    xlims!(ax, extrema(t)...)

    # keep small margins so bands don’t hit the frame when exported
    ax.xautolimitmargin[] = (0.02, 0.02)
    ax.yautolimitmargin[] = (0.02, 0.02)

    # (optional) update internal limits cache
    Makie.update_limits!(ax)

    ax.xticklabelrotation = π/6
    axislegend(ax, position = :rt)
    resize_to_layout!(fig)
    return fig
end

# --- 2) Monthly slicer ---
function plot_markets_month(ts_dt::Vector{DateTime}, t::Vector{Float64},
                            p_da1::Vector{Float64}, p_da2::Vector{Float64}, p_id::Vector{Float64},
                            s_da1::Vector{Float64}, s_da2::Vector{Float64}, s_id::Vector{Float64};
                            mon::Int, yr::Int)

    # (optional) update internal limits cache
    Makie.update_limits!(ax)

    idx = (Dates.month.(ts_dt) .== mon) .& (Dates.year.(ts_dt) .== yr)
    @assert any(idx) "No data for $(lpad(mon,2,'0')).$yr"

    tt = t[idx]
    n  = count(idx)

    fig = Figure(size = (1600, 800), padding = 28)
    ax  = Axis(fig[1, 1]; xlabel = "Zeit", ylabel = "Leistung [kW]",
               title = "Marktflüsse (Einkauf/Verkauf) – $(lpad(mon,2,'0')).$yr")

    # Einkauf (positive)
    band!(ax, tt, zeros(n), p_da1[idx]; color = (:steelblue, 0.1), label = "Einkauf DA Seq1")
    band!(ax, tt, zeros(n), p_da2[idx]; color = (:steelblue, 0.75), label = "Einkauf DA Seq2")
    band!(ax, tt, zeros(n), p_id[idx];  color = (:steelblue, 0.45), label = "Einkauf Intraday")

    # Verkauf (negative)
    band!(ax, tt, -s_da1[idx], zeros(n); color = (:tomato, 0.1), label = "Verkauf DA Seq1")
    band!(ax, tt, -s_da2[idx], zeros(n); color = (:tomato, 0.75), label = "Verkauf DA Seq2")
    band!(ax, tt, -s_id[idx],  zeros(n); color = (:tomato, 0.45), label = "Verkauf Intraday")

    # ---- generous y-limits so nothing touches the frame ----
    # consider only finite values
    all_pos = max.(0, max.(max.(p_da1, p_da2), p_id))           # purchases (>= 0)
    all_neg = min.(0, -max.(max.(s_da1, s_da2), s_id))          # sales as negative

    ymin = minimum(all_neg)
    ymax = maximum(all_pos)
    yrng = ymax - ymin

    # add a healthy padding: at least 50 kW or 12% of range
    pad = max(0.12 * (yrng > 0 ? yrng : 1.0), 50.0)

    # set limits after all series are added
    ylims!(ax, ymin - pad, ymax + pad)
    xlims!(ax, extrema(t)...)

    # keep small margins so bands don’t hit the frame when exported
    ax.xautolimitmargin[] = (0.02, 0.02)
    ax.yautolimitmargin[] = (0.02, 0.02)

    # (optional) update internal limits cache
    Makie.update_limits!(ax)

    ax.xticklabelrotation = π/6
    axislegend(ax, position = :rt)
    resize_to_layout!(fig)
    fig
end

# --- 3) Weekly slicer (Monday–Sunday by start date) ---
function plot_markets_week(ts_dt, t, p_da1, p_da2, p_id, s_da1, s_da2, s_id; start::Date, days::Int=7, title::Union{Nothing,String}=nothing)
    sdt = DateTime(start); edt = sdt + Day(days)
    idx = (ts_dt .>= sdt) .& (ts_dt .< edt)
    @assert any(idx) "No data for selected week"
    ttl = isnothing(title) ? "Marktflüsse (Einkauf/Verkauf) – $(Dates.format(sdt, dateformat"dd.mm.yyyy"))–$(Dates.format(edt - Day(1), dateformat"dd.mm"))" : title
    plot_markets_stack(t[idx], p_da1[idx], p_da2[idx], p_id[idx], s_da1[idx], s_da2[idx], s_id[idx]; title=ttl)
end