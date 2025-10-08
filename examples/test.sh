
echo "Testing lpsdp ... on Mantel. Solution is -1.5 "

../lpsdp manteln_n3_scale_3.dat-s  -i 5 -dc 

../lpsdpM manteln_n3_scale_3.dat-s  -i 5 -dc 

python3 ../lpsdp.py manteln_n3_scale_3.dat-s -dc

sage ../lpsdp.sage manteln_n3_scale_3.dat-s 

csdp manteln_n3_scale_3.dat-s  manteln_n3_scale_3.dat-s.result | tee manteln_n3_scale_3.dat-s.csdp.log

echo "Testing lpsdp ... on Tetrahedron. Solution using csdp is -0.56166722"

../lpsdp tetrahedron_n6.dat-s   -dc -s 100 -i 100

../lpsdpM tetrahedron_n6.dat-s  -dc  -s 100 -i 100

python3 ../lpsdp.py tetrahedron_n6.dat-s -s 100 -i 100 -dc

sage ../lpsdp.sage tetrahedron_n6.dat-s 100 20

csdp tetrahedron_n6.dat-s  tetrahedron_n6.dat-s.result | tee tetrahedron_n6.dat-s.csdp.log
