!
!//////////////////////////////////////////////////////
!
!   @File:    FluidData.f90
!   @Author:  Juan Manzanero (juan.manzanero@upm.es)
!   @Created: Wed Apr 18 18:07:28 2018
!   @Last revision date: Wed Jun 20 18:14:39 2018
!   @Last revision author: Juan Manzanero (j.manzanero1992@gmail.com)
!   @Last revision commit: 9c8ed8b6306ad0912cb55b510aa73d1610bb1cb5
!
!//////////////////////////////////////////////////////
!
module FluidData
#if defined(NAVIERSTOKES)
   use FluidData_NS
#elif defined(INCNS)
   use FluidData_iNS
#endif
#if defined(CAHNHILLIARD)
   use FluidData_CH
#endif
   implicit none

end module FluidData
