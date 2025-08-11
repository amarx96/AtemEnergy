# Readme File for Battery Optimizer
### PowerShell (Windows)
```powershell
# from the repo root
@'
# Battery Optimizer

## Overview
The **Battery Optimizer** is a Julia-based framework for economic and technical dispatch of battery storage. It maximizes project value under realistic market conditions (self-consumption and power markets).

## Key Features
- **Data ingestion:** load profiles, day-ahead/intraday prices, PV profiles.
- **Optimization model (JuMP):** LP/MILP for charge/discharge, arbitrage, and self-consumption.
- **Technical constraints:** power limits, energy capacity, round-trip efficiency, simple degradation.
- **Market scenarios:** stress tests across price and load cases.
- **Visualization:** SOC, market flows, revenues, and cost breakdowns.

## Tech Stack
- **Language:** Julia
- **Modeling:** JuMP
- **Solvers:** HiGHS (default) or Gurobi
- **Structure:**
  - `.source/` – core scripts and helpers
  - `data/` – inputs (prices, load, PV)
  - `Ergebnisse/` – results and reports
  - `Grafiken/` – plots

## Typical Use Cases
- Self-consumption with PV (commercial/industrial).
- Day-ahead vs. intraday arbitrage.
- Peak shaving + market participation.

## Why it matters
- Uses real market data and physical constraints.
- Scales from single assets to portfolios.
- Supports decarbonization and flexibility business models.

## Quick Start
```julia
using Pkg
Pkg.activate("."); Pkg.instantiate()

# entrypoint
include("Optimizer__Main__.jl")