#!/bin/sh
# ------------------------------------------------------------------------------
# 2023 Florian Boret
# https://github.com/igeofr/panoramax2pg
# CC BY-SA 4.0 : https://creativecommons.org/licenses/by-sa/4.0/deed.fr
#-------------------------------------------------------------------------------

# RECUPERATION DU TYPE DE DATA A INTEGRER
# if [ "$#" -ge 1 ]; then
#   if [ "$1" = "sequences" ] || [ "$1" = "pictures" ];
#   then
#     TYPE=$1
#     echo $TYPE
#   else
#   IFS= read -p "Type : " S_TYPE
#     if [ "$S_TYPE" = "sequences" ] || [ "$S_TYPE" = "pictures" ];
#     then
#       export TYPE=$S_TYPE
#       echo $TYPE
#     else
#       echo "Erreur de paramètre"
#       exit 0
#     fi
#   fi
# else
#   IFS= read -p "Type : " S_TYPE
#   if [ "$S_TYPE" = "sequences" ] || [ "$S_TYPE" = "pictures" ] ;
#   then
#     export TYPE=$S_TYPE
#     echo $TYPE
#   else
#     echo "Erreur de paramètre"
#     exit 0
#   fi
# fi

# VARIABLES DATES
export DATE_YM=$(date "+%Y%m")
export DATE_YMD=$(date "+%Y%m%d")

# LECTURE DU FICHIER DE CONFIGURATION
. "`dirname "$0"`/config.env"

# REPERTOIRE DE TRAVAIL
cd $REPER
echo $REPER

DATE_EPOCH=$(date -d $DATE_DEBUT +%s%3N)
echo $DATE_EPOCH

#-------------------------------------------------------------------------------
# BBOX ET IDENTIFICATION DES TUILES
# Source : https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
long2xtile(){
 long=$1
 zoom=$2
 echo -n "${long} ${zoom}" | awk '{ xtile = ($1 + 180.0) / 360 * 2.0^$2;
  xtile+=xtile<0?-0.5:0.5;
  printf("%d", xtile ) }'
}
lat2ytile() {
 lat=$1;
 zoom=$2;
 ytile=`echo "${lat} ${zoom}" | awk -v PI=3.14159265358979323846 '{
   tan_x=sin($1 * PI / 180.0)/cos($1 * PI / 180.0);
   ytile = (1 - log(tan_x + 1/cos($1 * PI/ 180))/PI)/2 * 2.0^$2;
   ytile+=ytile<0?-0.5:0.5;
   printf("%d", ytile ) }'`;
 echo -n "${ytile}";
}

XMIN=$(long2xtile $(echo $V_LONG_MIN | sed -e 's/\./,/g') $V_ZOOM)
XMAX=$(long2xtile $(echo $V_LONG_MAX | sed -e 's/\./,/g') $V_ZOOM)
YMIN=$(lat2ytile $(echo $V_LAT_MIN | sed -e 's/\./,/g') $V_ZOOM)
YMAX=$(lat2ytile $(echo $V_LAT_MAX | sed -e 's/\./,/g') $V_ZOOM)
echo $XMIN $YMIN $XMAX $YMAX

#-------------------------------------------------------------------------------
echo 'Debut du traitement des données de Panoramax'

file=$REPER'/'$DATE_YMD'_PANORAMAX_VT.gpkg'
rm $REPER'/'$DATE_YMD'_PANORAMAX_VT.'*

rm -r -d $REPER'/tuiles/'${DATE_YMD}

Z=$V_ZOOM
for X in $(seq $XMIN $XMAX);do
   for Y in $(seq $YMAX $YMIN);do

      PBF_FILE=${Z}'_'${X}'_'${Y}'.pbf'

      #-------------------------------------------------------------------------------
      URL="$V_URL/$Z/$X/$Y.pbf"
      #echo "https://panoramax.ign.fr/api/map/$Z/$X/$Y.pbf"

      mkdir $REPER'/tuiles/'${DATE_YMD}
      mkdir $REPER'/tuiles/'${DATE_YMD}'/'${Z}
      mkdir $REPER'/tuiles/'${DATE_YMD}'/'${Z}'/'${X}
      mkdir $REPER'/tuiles/'${DATE_YMD}'/'${Z}'/'${X}'/'${Y}

      # TELECHARGEMENT DES TUILES
      curl -w "%{http_code}" $URL --max-time 120 --connect-timeout 60 -o $REPER'/tuiles/'${DATE_YMD}'/'${Z}'/'${X}'/'${Y}'/'$PBF_FILE

      # FUSION EN GPKG
      ogr2ogr \
      -progress \
      -f 'GPKG' \
      -update -append \
      --debug ON \
      -addfields \
      -lco SPATIAL_INDEX=YES \
      $file \
      $REPER'/tuiles/'${DATE_YMD}'/'${Z}'/'${X}'/'${Y}'/'$PBF_FILE $LAYER \
      -nlt PROMOTE_TO_MULTI \
      -oo x=${X} -oo y=${Y} -oo z=${Z}

   done
done
#-------------------------------------------------------------------------------
echo 'Import dans PG'

# IMPORT PG
# if  [ "$TYPE" = "sequences" ]; then
    ogr2ogr \
        -append \
        -f "PostgreSQL" PG:"service='$C_SERVICE' schemas='$C_SCHEMA'" \
        -nln 'panoramax_vt_sequences' \
        -s_srs 'EPSG:3857' \
        -t_srs 'EPSG:2154' \
        $file 'sequences' \
        -where "account_id='$V_ORGANISATION'" \
        -dialect SQLITE \
        --config OGR_TRUNCATE YES \
        --config PG_USE_COPY YES \
        --debug ON \
        --config CPL_LOG './'$REPER_LOGS'/'$DATE_YMD'_panoramax_vt_sequences.log'
# elif [ "$TYPE" = "pictures" ]
# then
    ogr2ogr \
        -append \
        -f "PostgreSQL" PG:"service='$C_SERVICE' schemas='$C_SCHEMA'" \
        -nln 'panoramax_vt_pictures' \
        -s_srs 'EPSG:3857' \
        -t_srs 'EPSG:2154' \
        $file 'pictures' \
        -where "account_id='$V_ORGANISATION'" \
        -dialect SQLITE \
        --config OGR_TRUNCATE YES \
        --config PG_USE_COPY YES \
        --debug ON \
        --config CPL_LOG './'$REPER_LOGS'/'$DATE_YMD'_panoramax_vt_pictures.log'
# fi
echo 'Fin du traitement des données de Panoramax'
