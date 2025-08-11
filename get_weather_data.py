# %%
import xarray as xr
import matplotlib.pyplot as plt
from pathlib import Path
import pandas as pd
from atlite import Cutout
import atlite

# %%
# Load January NetCDF file
working_dir = Path("C:/Users/alex-/Desktop/BatteryStorage/Optimization/era5_solar_data")
file_path = "C:/Users/alex-/Desktop/BatteryStorage/Optimization/era5_solar_data/berlin_2024_01.nc"
ds = xr.open_dataset(file_path)

# Print dataset summary
print(ds)

# %%
# Define folder and file list
folder = Path("C:/Users/alex-/Desktop/BatteryStorage/Optimization/era5_solar_data")
files = sorted(folder.glob("berlin_2024_*.nc"))

# List to store datasets
datasets = []

# Load and append each dataset
for file in files:
    ds = xr.open_dataset(file)
    datasets.append(ds)

# Concatenate along the time dimension
combined_ds = xr.concat(datasets, dim="valid_time")

# Select the single grid point (since there's only one)
ssrd = combined_ds["ssrd"].isel(latitude=0, longitude=0)

# Plot the time series
ssrd.plot()
plt.title("Surface Solar Radiation - Berlin (2024)")
plt.ylabel("J/m²")
plt.xlabel("Time")
plt.show()

# %%
# Combine all months into a single dataset
combined_ds.to_netcdf(working_dir / "berlin_2024_combined.nc")


# %%
combined_ds
# %%
irradiance = ssrd.diff(dim="valid_time") / 3600  # W/m²
irradiance.head()
# %%
irradiance = irradiance.where(irradiance > 0, 0)  # remove negative jumps
# %%
# Save the irradiance data to a new NetCDF file
efficiency = 0.20
pv_output = irradiance * efficiency  # W/m²

# Calculate capacity factor
# Assuming a standard solar panel output of 1000 W/m² at peak efficiency
capacity_factor = pv_output / 1000  # unitless
capacity_factor.head()
# %%
cf_df = capacity_factor.to_series()
cf_df.index = pd.to_datetime(cf_df.index)
daily_cf = cf_df.resample("D").mean() * 100  # Umrechnung in Prozent


# Define path
plot_output_path = Path("C:/Users/alex-/Desktop/BatteryStorage/Optimization/Ergebnisse/DX_Center/solar_cf_berlin_2024_plot.png")

# Plot and save
plt.figure(figsize=(12, 4))
daily_cf.plot()
plt.title("Täglicher durchschnittlicher Kapazitätsfaktor von Solar-PV – Berlin 2024")
plt.ylabel("Kapazitätsfaktor (%)")
plt.xlabel("Datum")
plt.grid()
plt.tight_layout()
plt.savefig(plot_output_path)
plt.close()
# %% Export daily capacity factor to CSV
cf_df = capacity_factor.to_series()
cf_df_hourly = cf_df.resample("H").mean()
cf_df_hourly
# %%
cf_df_hourly_reset = cf_df_hourly.reset_index()
cf_df_hourly_reset.columns = ["Timestamp", "CapacityFactor"]
cf_df_hourly_reset["Timestamp"] = cf_df_hourly_reset["Timestamp"].dt.strftime("%d/%m/%Y %H:%M")
cf_df_hourly_reset
# %%
# Save to CSV
cf_df_hourly_reset.to_csv("C:/Users/alex-/Desktop/BatteryStorage/Optimization/Ergebnisse/DX_Center/solar_cf_berlin_2024_timestamped.csv", index=False)
# %%
