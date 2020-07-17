::
:: Batch script for thinning / smoothing defined areas (e.g. street surfaces) in a single huge LAS/LAZ file
::
:: Input is LAS file from e.g. pix4D and a shapefile with polygons of areas to be filtered
:: Output is one single LAS file where the polygon areas have been smoothed
::
:: Parameters:
::
:: STEP: size of grid in map units
:: PERCENTILE: use 50 for median
:: SHAPEFILE: shapefile with polygons of areas to be thinned
::
:: Processing steps:
:: lasclip creates point cloud with areas for thinning
:: lasclip creates point cloud with areas that remain untouched (inverse to the point cloud for thinning)
:: lastile creates temporary tiles for memory efficient thinning
:: lasthin filters the tiled point cloud for thinning using the median point (50 percentile) for each grid cell, cell size is definend by parameter STEP 
:: lasmerge merges the temporary (and filtered) tiles to one single point cloud for the smoothed areas
:: lasmerge merges the point cloud with the smoothed point data with the pointcloud of the untouched area into one single output las file
:: lasinfo replaces system / software tags in the output las file to avoid license issues
::
:: Steffen Vogt, 2020-06-24

echo off

::
:: specify parameters
::

:: name of shapefile with areas to be smoothed
set SHAPEFILE=strohmaier_auggen_clip_grube_2D.shp

:: allows you to run the script from other folders
::set PATH=%PATH%;C:\Programme\LASTools\bin;
set PATH=%PATH%;C:\LASTools\bin;

:: specify the resolution of the thinning grid
set STEP=2.00

:: specify the desired percentile
:: 50 is median
set PERCENTILE=50

:: specify the minimum number of points to be used for the percentile computation
set MINIMUM_POINTS=7


:: specify the size of the temporary tiles. it is important that
:: the tile size can be evenly divided by the grid resolution
:: meaning that TILE_SIZE/STEP is XXXX.0 without decimal digits 
set TILE_SIZE=500

:: specify the number of cores to run on
set NUM_CORES=5

:: specify the name for temporary directory
set TEMP_DIR=temp_dir_thinning

:: get the input file name for ouptut file name generation
set INFILE=%1

::
:: do the actual processing
::

:: clip and keep inside for thinning
lasclip -i %1 ^
        -poly %SHAPEFILE% ^
        -o temp_clip_inside_for_thinning.las

:: create temporary tile directory

rmdir %TEMP_DIR% /s /q
mkdir %TEMP_DIR%

:: create a temporary tiling with TILE_SIZE

lastile -i temp_clip_inside_for_thinning.las ^
        -tile_size %TILE_SIZE% ^
        -o %TEMP_DIR%\tile.laz -olaz

:: thins the tiles on NUM_CORES

lasthin -i %TEMP_DIR%\tile*.laz ^
        -step %STEP% ^
        -percentile %PERCENTILE% %MINIMUM_POINTS% ^
        -odix _p%PERCENTILE%_s%STEP% -olaz ^
        -cores %NUM_CORES%

:: recreate the (less huge) thinned LAS / LAZ file only for clip area

lasmerge -i %TEMP_DIR%\tile*_p%PERCENTILE%_s%STEP%.laz ^
         -o temp_clip_inside_thinned_median_s%STEP%.las

lasmerge -i temp_clip_inside_thinned_median_s%STEP%.las ^
         -o %1 -odix _median_s%STEP%

:: delete the temporary tile directory

rmdir %TEMP_DIR% /s /q

:: replace System / Software tags in output file

set OUTFILE=%INFILE:~0,-4%_median_s%STEP%.las

lasinfo -i %OUTFILE% ^
        -set_system_identifier "svGeo photogrammetry" ^
        -set_generating_software "svGeo las_pipe"

:: Write ASCII xyz file
las2txt -i %OUTFILE% -o %OUTFILE%.txt -parse xyz -sep comma