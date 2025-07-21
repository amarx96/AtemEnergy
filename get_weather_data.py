# %%
# Python   
import atlite
import logging 
# %%
# Enable logging
logging.basicConfig(level=logging.INFO)
# %%
# Dong Xuan Center in Berlin
cutout = atlite.Cutout(
    path="dongxuan-berlin-2022.nc",
    module="era5",
    x=slice(13.2801, 13.6801),  # Longitude ±0.2°
    y=slice(52.341, 52.741),    # Latitude ±0.2°
    time="2022",
    chunks={"time": 100},       # recommended chunk size
)