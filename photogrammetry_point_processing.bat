::
:: Batch script for converting photogrammetry points into a
:: number of products with a tile-based multi-core batch pipeline
:: heavily based on example script photogrammtry_point_processing_example01.bat from LAStools
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
:: last modified 2020-07-22





:: add LAStools\bin directory to PATH to run script from anywhere
set PATH=%PATH%;C:\LAStools\bin

:: specify the number of cores to use
set NUM_CORES=4

:: get input file name from first command line argument
set INFILE=%1
:: input file name without extension for automatic output file name generation
set INFILE_PREFIX=%INFILE:~0,-4%





:: create a lasinfo report and a 0.25 m RGB raster from input LAZ file

if exist .\01_quality rmdir .\01_quality /s /q
mkdir .\01_quality

lasinfo -i %INFILE% ^
        -cd ^
        -cpu64 ^
        -o 01_quality\%INFILE_PREFIX%.txt

lasgrid -i %INFILE% ^
        -step 0.25 ^
        -rgb ^
        -scale_RGB_down ^
        -fill 1 ^
        -o 01_quality\%INFILE_PREFIX%.png

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
        -step 0.9 ^
        -percentile 20 20 ^
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
          -town -ultra_fine ^
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

:: classify the lowest points per 25 cm by 25 cm cell that is *not*
:: noise (i.e. classification other than 7) as 8 using lasthin 

if exist .\05_tiles_thinned_lowest rmdir .\05_tiles_thinned_lowest /s /q
mkdir .\05_tiles_thinned_lowest

lasthin -i 04_tiles_denoised\%INFILE_PREFIX%*.laz ^
        -ignore_class 7 ^
        -step 0.25 ^
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
          -town -extra_fine -bulge 0.1 ^
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
        -step 0.25 ^
        -use_tile_bb ^
        -odir 07_tiles_dtm -olaz ^
        -cpu64 ^
        -cores %NUM_CORES%

:: we merge the gridded LAZ files for the DTM into one input and create
:: a 25cm hillshaded DTM raster in PNG format

blast2dem -i 07_tiles_dtm\%INFILE_PREFIX%*.laz -merged ^
          -hillshade ^
          -step 0.25 ^
          -o dtm_hillshaded.png

:: the highest points per 25 cm by 25 cm cell that is *not* a noise point
:: (i.e. classification other than 7) is classified as 8 with lasthin 

if exist .\08_tiles_thinned_highest rmdir .\08_tiles_thinned_highest /s /q
mkdir .\08_tiles_thinned_highest

lasthin -i 04_tiles_denoised\%INFILE_PREFIX%*.laz ^
        -ignore_class 7 ^
        -step 0.25 ^
        -highest ^
        -classify_as 8 ^
        -odir 08_tiles_thinned_highest -olaz ^
        -cpu64 ^
        -cores %NUM_CORES%

:: interpolate points classified as 8 into a TIN and raster a 25 cm DSM
:: but cutting out only the center 200 meter by 200 meter tile but not
:: rasterizing the buffers. the DSM raster is stored as gridded LAZ for
:: maximal compression

if exist .\09_tiles_dsm rmdir .\09_tiles_dsm /s /q
mkdir .\09_tiles_dsm

las2dem -i 08_tiles_thinned_highest\%INFILE_PREFIX%*.laz ^
        -keep_class 8 ^
        -step 0.25 ^
        -use_tile_bb ^
        -odir 09_tiles_dsm -olaz ^
        -cpu64 ^
        -cores %NUM_CORES%

:: we merge the gridded LAZ files for the DSM into one input and create
:: a 25cm hillshaded DSM raster in PNG format

blast2dem -i 09_tiles_dsm\%INFILE_PREFIX%*.laz -merged ^
          -hillshade ^
          -step 0.25 ^
          -o dsm_hillshaded.png








:: merge laz output tiles into single las file for convenient use in other software
:: and subsequently remove intermediate directories and files

if exist .\10_las_output rmdir .\10_las_output /s /q
mkdir .\10_las_output

:: delete raw tiles
if exist .\02_tiles_raw rmdir .\02_tiles_raw /s /q

:: for each processing step merge processed tiles into one las file and delete tiles
if exist .\03_tiles_temp1_no_buffer rmdir .\03_tiles_temp1_no_buffer /s /q
mkdir .\03_tiles_temp1_no_buffer
lastile -i .\03_tiles_temp1\*.laz ^
        -odir .\03_tiles_temp1_no_buffer ^
        -remove_buffer ^
        -olaz ^
        -cpu64
lasmerge .\03_tiles_temp1_no_buffer\*.laz ^
       -o .\10_las_output\03_temp1_%INFILE_PREFIX%.las ^
       -cpu64
rmdir .\03_tiles_temp1_no_buffer /s /q
rmdir .\03_tiles_temp1 /s /q

if exist .\03_tiles_temp2_no_buffer rmdir .\03_tiles_temp2_no_buffer /s /q
mkdir .\03_tiles_temp2_no_buffer
lastile -i .\03_tiles_temp2\*.laz ^
        -odir .\03_tiles_temp2_no_buffer ^
        -remove_buffer ^
        -olaz ^
        -cpu64
lasmerge .\03_tiles_temp2_no_buffer\*.laz ^
       -o .\10_las_output\03_temp2_%INFILE_PREFIX%.las ^
       -cpu64
rmdir .\03_tiles_temp2_no_buffer /s /q
rmdir .\03_tiles_temp2 /s /q

if exist .\03_tiles_temp3_no_buffer rmdir .\03_tiles_temp3_no_buffer /s /q
mkdir .\03_tiles_temp3_no_buffer
lastile -i .\03_tiles_temp3\*.laz ^
        -odir .\03_tiles_temp3_no_buffer ^
        -remove_buffer ^
        -olaz ^
        -cpu64
lasmerge .\03_tiles_temp3_no_buffer\*.laz ^
       -o .\10_las_output\03_temp3_%INFILE_PREFIX%.las ^
       -cpu64
rmdir .\03_tiles_temp3_no_buffer /s /q
rmdir .\03_tiles_temp3 /s /q

if exist .\04_tiles_denoised_no_buffer rmdir .\04_tiles_denoised_no_buffer /s /q
mkdir .\04_tiles_denoised_no_buffer
lastile -i .\04_tiles_denoised\*.laz ^
        -odir .\04_tiles_denoised_no_buffer ^
        -remove_buffer ^
        -olaz ^
        -cpu64
lasmerge .\04_tiles_denoised_no_buffer\*.laz ^
       -o .\10_las_output\04_denoised_%INFILE_PREFIX%.las ^
       -cpu64
rmdir .\04_tiles_denoised_no_buffer /s /q
rmdir .\04_tiles_denoised /s /q

if exist .\05_tiles_thinned_lowest_no_buffer rmdir .\05_tiles_thinned_lowest_no_buffer /s /q
mkdir .\05_tiles_thinned_lowest_no_buffer
lastile -i .\05_tiles_thinned_lowest\*.laz ^
        -odir .\05_tiles_thinned_lowest_no_buffer ^
        -remove_buffer ^
        -olaz ^
        -cpu64
lasmerge .\05_tiles_thinned_lowest_no_buffer\*.laz ^
       -o .\10_las_output\05_thinned_lowest_%INFILE_PREFIX%.las ^
       -cpu64
rmdir .\05_tiles_thinned_lowest_no_buffer /s /q
rmdir .\05_tiles_thinned_lowest /s /q

if exist .\06_tiles_ground_no_buffer rmdir .\06_tiles_ground_no_buffer /s /q
mkdir .\06_tiles_ground_no_buffer
lastile -i .\06_tiles_ground\*.laz ^
        -odir .\06_tiles_ground_no_buffer ^
        -remove_buffer ^
        -olaz ^
        -cpu64
lasmerge .\06_tiles_ground_no_buffer\*.laz ^
       -o .\10_las_output\06_ground_%INFILE_PREFIX%.las ^
       -cpu64
rmdir .\06_tiles_ground_no_buffer /s /q
rmdir .\06_tiles_ground /s /q


lasmerge .\07_tiles_dtm\*.laz ^
       -o .\10_las_output\07_dtm_%INFILE_PREFIX%.las ^
       -cpu64
rmdir .\07_tiles_dtm /s /q

if exist .\08_tiles_thinned_highest_no_buffer rmdir .\08_tiles_thinned_highest_no_buffer /s /q
mkdir .\08_tiles_thinned_highest_no_buffer
lastile -i .\08_tiles_thinned_highest\*.laz ^
        -odir .\08_tiles_thinned_highest_no_buffer ^
        -remove_buffer ^
        -olaz ^
        -cpu64
lasmerge .\08_tiles_thinned_highest_no_buffer\*.laz ^
       -o .\10_las_output\08_thinned_highest_%INFILE_PREFIX%.las ^
       -cpu64
rmdir .\08_tiles_thinned_highest_no_buffer /s /q
rmdir .\08_tiles_thinned_highest /s /q

lasmerge .\09_tiles_dsm\*.laz ^
       -o .\10_las_output\09_dsm_%INFILE_PREFIX%.las ^
       -cpu64
rmdir .\09_tiles_dsm /s /q







