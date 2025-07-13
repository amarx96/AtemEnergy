# install_and_import.jl

# List of required packages
required_packages = [
    "JuMP",
    "DataStructures",
    "HiGHS",
    "CSV",
    "DataFrames",
    "Statistics",  # This is part of Julia's standard library and doesn't need installation
    "Plots",
    "StatsPlots"
]

# Install missing packages
import Pkg
for pkg in required_packages
    if !(pkg in keys(Pkg.installed()))
        println("Installing: $pkg")
        Pkg.add(pkg)
    end
end

# Import packages
using JuMP
using DataStructures
using HiGHS
using CSV
using DataFrames
using Statistics
using Plots
using Plots.Measures
using StatsPlots