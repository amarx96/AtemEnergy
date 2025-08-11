# %%
import cdsapi
import cdsapi
import calendar
from pathlib import Path
print("cdsapi is installed and ready!")

#%%
# This script retrieves surface solar radiation data for Berlin in 2024# Set up CDS API client
c = cdsapi.Client()

# Define the exact output path
output_folder = Path("C:/Users/alex-/Desktop/BatteryStorage/Optimization/WeatherData")
output_folder.mkdir(parents=True, exist_ok=True)

# Define small box around Berlin (North, West, South, East)
area = [52.55, 13.45, 52.50, 13.50]

# %%
# Loop through all months
for month in range(1, 13):
    month_str = str(month).zfill(2)
    last_day = calendar.monthrange(2024, month)[1]

    print(f"📦 Requesting data for 2024-{month_str}...")

    c.retrieve(
        'reanalysis-era5-single-levels',
        {
            'product_type': 'reanalysis',
            'variable':[
            '2m_temperature',
            'surface_pressure',
            'surface_solar_radiation_downwards',
            'surface_thermal_radiation_downwards',
            'top_net_solar_radiation',
            'top_net_thermal_radiation'
        ],
            'year': '2024',
            'month': month_str,
            'day': [f"{d:02d}" for d in range(1, last_day + 1)],
            'time': [f"{h:02d}:00" for h in range(24)],
            'format': 'netcdf',
            'area': area,
        },
        str(output_folder / f"berlin_2024_{month_str}.nc")
    )

    print(f"✅ Saved: berlin_2024_{month_str}.nc")


# %%
