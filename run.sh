#!/bin/sh
python --version
# cd ~/flags/zap-scrape
# python tfit_2020.py  12000 8000 aluguel_imoveis_rj_2018_07_29.csv
CWD=$PWD
cd ~/flags/zap-scrape
python tfit_2020.py 8000 8000 aluguel_zap_rj_fev_2021.csv 