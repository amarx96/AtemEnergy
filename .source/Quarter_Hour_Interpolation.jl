using Dates
using DataFrames
using Interpolations

function interp_qh(Solar_CF::AbstractDict)
    # keys may be String "dd/mm/yyyy HH:MM" or DateTime
    ks = collect(keys(Solar_CF))
    ts = ks[1] isa DateTime ? convert.(DateTime, ks) :
                              DateTime.(ks, dateformat"dd/mm/yyyy HH:MM")
    vs = Float64.(getindex.(Ref(Solar_CF), ks))

    # sort
    p = sortperm(ts); ts = ts[p]; vs = vs[p]

    # linear interpolation on numeric time axis
    x = Float64.(Dates.value.(ts))
    itp = Interpolations.extrapolate(
            interpolate((x,), vs, Gridded(Linear())),
            Line())

    # 15-minute grid and evaluation
    grid = collect(first(ts):Minute(15):last(ts))
    cf   = itp.(Float64.(Dates.value.(grid)))

    return DataFrame(Timestamp = grid, CapacityFactor = cf)
end
