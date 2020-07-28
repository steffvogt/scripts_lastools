::
:: Batch script for converting photogrammetry points into a
:: number of products with a tile-based multi-core batch pipeline
:: heavily based on example script photogrammtry_point_processing_example01.bat from LAStools
::
:: PRODUCTION VERSION, write out only DTM *.las file and DTM *.xyz ASCII file
:: When testing different paramter values use the other version of the script, that writes out all intermediate products
::
:: Input is LAS file from e.g. pix4D 
:: Output is ... (tbd)
::
:: Parameters:
::
:: INFILE: unclassified input LAS file from photogrammetry
:: 
:: USAGE: photogrammtry_points_processing.bat my_uav_pointcloud.las
::
::
:: Processing steps:
:: ... (tbd)
::
:: Steffen Vogt, 2020-07-17
:: last modified 2020-07-28


:: Parameters
::
::



echo off

:: add LAStools\bin directory to PATH to run script from anywhere
set PATH=%PATH%;C:\LAStools\bin

:: specify the number of cores to use
set NUM_CORES=4

:: specifiy grid cell size
set CELL_SIZE=0.50



::  The lasground tool also produces excellent results for town or cities
::  but buildings larger than the step size can be problematic.
::  The default step size is 5 meters, which is good for forest
::  or mountains. For towns or flat terrains the step
::  size could increased to 10 meters. For cities or warehouses
::  the step size could increased to 25 meters. For very
::  large cities the step size could be increased
::  to 50 meters.
::
:: specifiy the lasground step size directly
set LASGROUND_STEP=5.0

:: For very steep hills you can intensify the search for initial
:: ground points with '-fine' or '-extra_fine' and similarly for
:: flat terrains you can simplify the search with '-coarse' or
:: '-extra_coarse' but try the default setting first. 
::
::
:: specify the lasground initial ground point search strategy (typically extra_fine)
:: extra_coarse / coarse / fine / extra_fine / ultra_fine / hyper_fine
set LASGROUND_INITIAL_GROUNDPOINT_STRATEGY=extra_fine

:: Another parameter of interest is the '-bulge' parameter
:: that specifies how much the TIN is allowed to bulge up when
:: including points as it is getting refined. The default bulge
:: is one tenth of the step for step sizes larger than 5 meters
:: and one fifth of the step otherwise. Especially for ground-
:: classification of non-LiDAR points such as dense-matching or
:: photogrammetry output by Agisoft of Pix4D the fine-tuning of
:: this parameter can produce great results.

:: specifiy the lasground bulge directly (typically 0.1)
set LASGROUND_BULGE=0.1



:: specify grid cell size for below ground noise filtering (typically 3-5 times the grid cell size)
set FILTER_BELOW_GROUND_CELL_SIZE=0.90

:: specify the percentile value for below ground noise filtering (typically 20)
set FILTER_BELOW_GROUND_PERCENTILE=20

:: specify the minimum number of points per grid cell for below ground noise filtering (typically 20)
set FILTER_BELOW_GROUND_MIN_POINTS=20

:: specify the lasground stepsize for below ground noise filtering (typically 5.0)
set FILTER_BELOW_GROUND_LASGROUND_STEP=5.0


:: For very steep hills you can intensify the search for initial
:: ground points with '-fine' or '-extra_fine' and similarly for
:: flat terrains you can simplify the search with '-coarse' or
:: '-extra_coarse' but try the default setting first. 
:: For very steep hills you can intensify the search for initial
::
:: specify the lasground initial ground point search strategy for below ground noise filtering (typically ultra_fine)
:: extra_coarse / coarse / fine / extra_fine / ultra_fine / hyper_fine
set FILTER_BELOW_GROUND_LASGROUND_INITIAL_GROUNDPOINT_STRATEGY=ultra_fine



:: get input file name from first command line argument
set INFILE=%1
:: input file name without extension for automatic output file name generation
set INFILE_PREFIX=%INFILE:~0,-4%



set DATE_START=%date%
set TIME_START=%time%

:: create a lasinfo report and a 0.25 m RGB raster from input LAZ file

::if exist .\01_quality rmdir .\01_quality /s /q
::mkdir .\01_quality

lasinfo -i %INFILE% ^
        -cd ^
        -cpu64 ^
        -o %INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_infile_quality.txt

lasgrid -i %INFILE% ^
        -step %CELL_SIZE% ^
        -rgb ^
        -scale_RGB_down ^
        -fill 1 ^
        -o %INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_infile_quickview.png

:: use lastile to create a buffered tiling from the original
:: photogrammetry points. We use '-tile_size 200'
:: to specify the tile size and request a buffer of 30 meters
:: around every tile with '-buffer 30' and '-flag_as_withheld'
:: all the buffer points so they can easily be dropped later.
:: the '-olaz' flag requests LASzip compressed output tiles to
:: lower the I/O bottleneck.

if exist .\02_tiles_raw rmdir .\02_tiles_raw /s /q
mkdir .\02_tiles_raw

lastile -i %INFILE% ^
        -tile_size 200 -buffer 30 -flag_as_withheld ^
        -cpu64 ^
        -o 02_tiles_raw\%INFILE_PREFIX%.laz -olaz

if exist .\03_tiles_temp1 rmdir .\03_tiles_temp1 /s /q
mkdir .\03_tiles_temp1

:: give the point closest to the 20th elevation percentile per
:: 90 cm by 90 cm cell the classification code 8 (but only do
:: this for cells containing 20 or more points) using lasthin

lasthin -i 02_tiles_raw\%INFILE_PREFIX%*.laz ^
        -step %FILTER_BELOW_GROUND_CELL_SIZE% ^
        -percentile %FILTER_BELOW_GROUND_PERCENTILE% %FILTER_BELOW_GROUND_MIN_POINTS% ^
        -classify_as 8 ^
        -odir 03_tiles_temp1 -olaz ^
        -cpu64 ^
        -cores %NUM_CORES%

:: considering only points with classification code 8 (ignoring
:: those with classification code 0) change to code from 8 to 12
:: for all "overly isolated" points using lasnoise. the check
:: for isolation uses cells of size 200 cm by 200 cm by 50 cm 
:: and marks points in cells whose neighbourhood of 27 cells has
:: only 3 or fewer points in total (see lasnoise_README.txt)

if exist .\03_tiles_temp2 rmdir .\03_tiles_temp2 /s /q
mkdir .\03_tiles_temp2

lasnoise -i 03_tiles_temp1\%INFILE_PREFIX%*.laz ^
         -ignore_class 0 ^
         -step_xy 2 -step_z 0.5 -isolated 3 ^
         -classify_as 12 ^
         -odir 03_tiles_temp2 -olaz ^
         -cpu64 ^
         -cores %NUM_CORES%

:: considering only the surviving points with classification
:: code 8 (ignoring those with classification code 0 or 12)
:: change their classification code from 8 either to ground (2)
:: or to non-ground (1) using lasground. the temporary ground
:: surface defined by the resulting ground points will be used
:: to classify points below it as noise in the next step.

if exist .\03_tiles_temp3 rmdir .\03_tiles_temp3 /s /q
mkdir .\03_tiles_temp3

lasground_new -i 03_tiles_temp2\%INFILE_PREFIX%*.laz ^
          -ignore_class 0 12 ^
          -step %FILTER_BELOW_GROUND_LASGROUND_STEP% ^
          -%FILTER_BELOW_GROUND_LASGROUND_INITIAL_GROUNDPOINT_STRATEGY% ^
          -odir 03_tiles_temp3 -olaz ^
          -cpu64 ^
          -cores %NUM_CORES%

:: classify all points that are 20 cm or more below the surface
:: that results from Delaunay triangulating the temporary ground
:: points as noise (7) and all others as unclassified (1)
:: lasheight uses only the ground points (2) of the input file

if exist .\04_tiles_denoised rmdir .\04_tiles_denoised /s /q
mkdir .\04_tiles_denoised

lasheight -i 03_tiles_temp3\%INFILE_PREFIX%*.laz ^
          -classify_below -0.2 7 ^
          -classify_above -0.2 1 ^
          -odir 04_tiles_denoised -olaz ^
          -cpu64 ^
          -cores %NUM_CORES%

:: classify the lowest points per CELL_SIZE by CELL_SIZE cell that is *not*
:: noise (i.e. classification other than 7) as 8 using lasthin 

if exist .\05_tiles_thinned_lowest rmdir .\05_tiles_thinned_lowest /s /q
mkdir .\05_tiles_thinned_lowest

lasthin -i 04_tiles_denoised\%INFILE_PREFIX%*.laz ^
        -ignore_class 7 ^
        -step %CELL_SIZE% ^
        -lowest ^
        -classify_as 8 ^
        -odir 05_tiles_thinned_lowest -olaz ^
        -cpu64 ^
        -cores %NUM_CORES%

:: classify points considering only the points with classification code 8 
:: (i.e. ignore classification 1 and 7) into ground (2) and non-ground (1) 
:: points using lasground with options '-town -extra_fine -bulge 0.1' 

if exist .\06_tiles_ground rmdir .\06_tiles_ground /s /q
mkdir .\06_tiles_ground

lasground_new -i 05_tiles_thinned_lowest\%INFILE_PREFIX%*.laz ^
          -ignore_class 1 7 ^
          -step %LASGROUND_STEP% ^
          -%LASGROUND_INITIAL_GROUNDPOINT_STRATEGY% ^
          -bulge %LASGROUND_BULGE% ^
          -odir 06_tiles_ground -olaz ^
          -cpu64 ^
          -cores %NUM_CORES%

:: interpolate points classified as 2 into a TIN and raster a 25 cm DTM
:: but cutting out only the center 200 meter by 200 meter tile but not
:: rasterizing the buffers. the DTM raster is stored as gridded LAZ for
:: maximal compression

if exist .\07_tiles_dtm rmdir .\07_tiles_dtm /s /q
mkdir .\07_tiles_dtm

las2dem -i 06_tiles_ground\%INFILE_PREFIX%*.laz ^
        -keep_class 2 ^
        -step %CELL_SIZE% ^
        -use_tile_bb ^
        -odir 07_tiles_dtm -olaz ^
        -cpu64 ^
        -cores %NUM_CORES%

:: we merge the gridded LAZ files for the DTM into one input and create
:: a 25cm hillshaded DTM raster in PNG format

blast2dem -i 07_tiles_dtm\%INFILE_PREFIX%*.laz -merged ^
          -hillshade ^
          -step %CELL_SIZE% ^
          -o %INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_dtm_hillshaded.png



:: merge DTM tiles into one las file and delete intermediate DTM tiles

lasmerge .\07_tiles_dtm\*.laz ^
       -o .\%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_dtm.las ^
       -cpu64

:: remove intermediate directories and files

if exist .\02_tiles_raw rmdir .\02_tiles_raw /s /q
if exist .\03_tiles_temp1 rmdir .\03_tiles_temp1 /s /q
if exist .\03_tiles_temp2 rmdir .\03_tiles_temp2 /s /q
if exist .\03_tiles_temp3 rmdir .\03_tiles_temp3 /s /q
if exist .\04_tiles_denoised rmdir .\04_tiles_denoised /s /q
if exist .\05_tiles_thinned_lowest rmdir .\05_tiles_thinned_lowest /s /q
if exist .\06_tiles_ground rmdir .\06_tiles_ground /s /q
if exist .\07_tiles_dtm rmdir .\07_tiles_dtm /s /q

:: replace System / Software tags in output las file

lasinfo -i %INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_dtm.las ^
        -set_system_identifier "svGeo photogrammetry" ^
        -set_generating_software "svGeo las_pipe"

:: Write commma separated ASCII xyz file

las2txt -i %INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_dtm.las ^
        -o %INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_dtm.txt ^
        -parse xyz ^
        -sep comma ^
        -cpu64



:: Write text file with processing parameters

>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo Processing started at: %DATE_START% %TIME_START%
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo Processing ended at:   %date% %time%
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo input LAS file: %INFILE%
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo output LAS DTM file: %INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_dtm.las
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo output XYZ DTM file: %INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_dtm.xyz
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo. 
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo cell size: %CELL_SIZE%
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo lasground step size: %LASGROUND_STEP%
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo lasground initial ground point search strategy: %LASGROUND_INITIAL_GROUNDPOINT_STRATEGY%
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo lasground bulge: %LASGROUND_BULGE%
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo. 
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo Below ground noise filter cell size: %FILTER_BELOW_GROUND_CELL_SIZE%
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo Below ground noise filter lasground step size: %FILTER_BELOW_GROUND_LASGROUND_STEP%
>>%INFILE_PREFIX%_cell%CELL_SIZE%_lgstep%LASGROUND_STEP%_lgbulge%LASGROUND_BULGE%_processing_parameters.txt echo Below ground noise filter lasground initial ground point strategy: %FILTER_BELOW_GROUND_LASGROUND_INITIAL_GROUNDPOINT_STRATEGY%




