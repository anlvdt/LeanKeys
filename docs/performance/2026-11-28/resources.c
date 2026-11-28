#include <libproc.h>
#include <sys/resource.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
int main(int n,char**v){struct rusage_info_v2 a,b; int p=atoi(v[1]); if(proc_pid_rusage(p,RUSAGE_INFO_V2,(rusage_info_t*)&a))return 1;sleep(30);if(proc_pid_rusage(p,RUSAGE_INFO_V2,(rusage_info_t*)&b))return 1;printf("wakeups idle %llu interrupt %llu cpu ms %.2f footprint MiB %.2f\n",b.ri_pkg_idle_wkups-a.ri_pkg_idle_wkups,b.ri_interrupt_wkups-a.ri_interrupt_wkups,(b.ri_user_time+b.ri_system_time-a.ri_user_time-a.ri_system_time)/1e6,b.ri_phys_footprint/1048576.);}
