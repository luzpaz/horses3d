!
!//////////////////////////////////////////////////////
!
!   @File:    ProblemFile.f90
!   @Author:  Juan Manzanero (juan.manzanero@upm.es)
!   @Created: Sat Oct 28 12:16:18 2017
!   @Last revision date: Sun Oct 29 17:43:40 2017
!   @Last revision author: Juan Manzanero (juan.manzanero@upm.es)
!   @Last revision commit: 923d934f3c0893856fbedc5cb9f9abe65851c070
!
!//////////////////////////////////////////////////////
!
!
!////////////////////////////////////////////////////////////////////////
!
!      ProblemFile.f90
!      Created: June 26, 2015 at 8:47 AM 
!      By: David Kopriva  
!
!      The Problem File contains user defined procedures
!      that are used to "personalize" i.e. define a specific
!      problem to be solved. These procedures include initial conditions,
!      exact solutions (e.g. for tests), etc. and allow modifications 
!      without having to modify the main code.
!
!      The procedures, *even if empty* that must be defined are
!
!      UserDefinedSetUp
!      UserDefinedInitialCondition(mesh)
!      UserDefinedPeriodicOperation(mesh)
!      UserDefinedFinalize(mesh)
!      UserDefinedTermination
!
!//////////////////////////////////////////////////////////////////////// 
! 
#include "Includes.h"
module UserDefinedDataStorage
   use SMConstants
   
   private
   public   c1, c2, c3, c4, c5

   real(kind=RP)  :: c1
   real(kind=RP)  :: c2 
   real(kind=RP)  :: c3
   real(kind=RP)  :: c4
   real(kind=RP)  :: c5

end module UserDefinedDataStorage

         SUBROUTINE UserDefinedStartup
!
!        --------------------------------
!        Called before any other routines
!        --------------------------------
!
            IMPLICIT NONE  
         END SUBROUTINE UserDefinedStartup
!
!//////////////////////////////////////////////////////////////////////// 
! 
         SUBROUTINE UserDefinedFinalSetup(mesh , thermodynamics_, &
                                                 dimensionless_, &
                                                     refValues_ )
!
!           ----------------------------------------------------------------------
!           Called after the mesh is read in to allow mesh related initializations
!           or memory allocations.
!           ----------------------------------------------------------------------
!
            USE HexMeshClass
            use PhysicsStorage
            use UserDefinedDataStorage
            IMPLICIT NONE
            CLASS(HexMesh)                      :: mesh
            type(Thermodynamics_t), intent(in)  :: thermodynamics_
            type(Dimensionless_t),  intent(in)  :: dimensionless_
            type(RefValues_t),      intent(in)  :: refValues_


            c1 =  0.1_RP * PI
            c2 = -0.2_RP * PI + 0.05_RP * PI * (1.0_RP + 5.0_RP * thermodynamics_ % gamma)
            c3 = 0.01_RP * PI * ( thermodynamics_ % gamma - 1.0_RP ) 
            c4 = 0.05_RP * ( -16.0_RP * PI + PI * (9.0_RP + 15.0_RP * thermodynamics_ % gamma ))
            c5 = 0.01_RP * ( 3.0_RP * PI * thermodynamics_ % gamma - 2.0_RP * PI )

         END SUBROUTINE UserDefinedFinalSetup
!
!//////////////////////////////////////////////////////////////////////// 
! 
         SUBROUTINE UserDefinedInitialCondition(mesh, thermodynamics_, &
                                                      dimensionless_, &
                                                          refValues_  )
!
!           ------------------------------------------------
!           Called to set the initial condition for the flow
!              - By default it sets an uniform initial
!                 condition.
!           ------------------------------------------------
!
            USE SMConstants
            use PhysicsStorage
            use HexMeshClass
            implicit none
            class(HexMesh)                      :: mesh
            type(Thermodynamics_t), intent(in)  :: thermodynamics_
            type(Dimensionless_t),  intent(in)  :: dimensionless_
            type(RefValues_t),      intent(in)  :: refValues_
!
!           ---------------
!           Local variables
!           ---------------
!
            integer        :: eID, i, j, k
            real(kind=RP)  :: qq, u, v, w, p, x(NDIM)
            real(kind=RP)  :: Q(N_EQN), phi, theta

            associate ( gammaM2 => dimensionless_ % gammaM2, &
                        gamma => thermodynamics_ % gamma )
      
            do eID = 1, mesh % no_of_elements
               associate( Nx => mesh % elements(eID) % Nxyz(1), &
                          Ny => mesh % elements(eID) % Nxyz(2), &
                          Nz => mesh % elements(eID) % Nxyz(3) )
               do k = 0, Nz;  do j = 0, Ny;  do i = 0, Nx 
                  x = mesh % elements(eID) % geom % x(:,i,j,k)

                  Q(1) = ( 2.0_RP + 0.1_RP * sin(PI*(x(1) + x(2) - 1.0_RP + x(3))))
                  Q(2) = Q(1)
                  Q(3) = Q(1)
                  Q(4) = Q(1)
                  Q(5) = POW2(Q(1))

                  mesh % elements(eID) % storage % Q(:,i,j,k) = Q 
               end do;        end do;        end do
               end associate
            end do

            end associate
            
         END SUBROUTINE UserDefinedInitialCondition

         subroutine UserDefinedState1(x, t, nHat, Q, thermodynamics_, dimensionless_, refValues_)
!
!           -------------------------------------------------
!           Used to define an user defined boundary condition
!           -------------------------------------------------
!
            use SMConstants
            use PhysicsStorage
            implicit none
            real(kind=RP), intent(in)     :: x(NDIM)
            real(kind=RP), intent(in)     :: t
            real(kind=RP), intent(in)     :: nHat(NDIM)
            real(kind=RP), intent(inout)  :: Q(N_EQN)
            type(Thermodynamics_t),    intent(in)  :: thermodynamics_
            type(Dimensionless_t),     intent(in)  :: dimensionless_
            type(RefValues_t),         intent(in)  :: refValues_
         end subroutine UserDefinedState1

         subroutine UserDefinedNeumann(x, t, nHat, U_x, U_y, U_z)
!
!           --------------------------------------------------------
!           Used to define a Neumann user defined boundary condition
!           --------------------------------------------------------
!
            use SMConstants
            use PhysicsStorage
            implicit none
            real(kind=RP), intent(in)     :: x(NDIM)
            real(kind=RP), intent(in)     :: t
            real(kind=RP), intent(in)     :: nHat(NDIM)
            real(kind=RP), intent(inout)  :: U_x(N_GRAD_EQN)
            real(kind=RP), intent(inout)  :: U_y(N_GRAD_EQN)
            real(kind=RP), intent(inout)  :: U_z(N_GRAD_EQN)
         end subroutine UserDefinedNeumann

!
!//////////////////////////////////////////////////////////////////////// 
! 
         SUBROUTINE UserDefinedPeriodicOperation(mesh, time, Monitors)
!
!           ----------------------------------------------------------
!           Called at the output interval to allow periodic operations
!           to be performed
!           ----------------------------------------------------------
!
            USE HexMeshClass
            use MonitorsClass
            IMPLICIT NONE
            CLASS(HexMesh)               :: mesh
            REAL(KIND=RP)                :: time
            type(Monitor_t), intent(in) :: monitors
            
         END SUBROUTINE UserDefinedPeriodicOperation
!
!//////////////////////////////////////////////////////////////////////// 
! 
         subroutine UserDefinedSourceTerm(mesh, time, thermodynamics_, dimensionless_, refValues_)
!
!           --------------------------------------------
!           Called to apply source terms to the equation
!           --------------------------------------------
!
            USE HexMeshClass
            use PhysicsStorage
            use UserDefinedDataStorage
            IMPLICIT NONE
            CLASS(HexMesh)                        :: mesh
            REAL(KIND=RP)                         :: time
            type(Thermodynamics_t),    intent(in) :: thermodynamics_
            type(Dimensionless_t),     intent(in) :: dimensionless_
            type(RefValues_t),         intent(in) :: refValues_
!
!           ---------------
!           Local variables
!           ---------------
!
            integer  :: i, j, k, eID
            real(kind=RP)  :: S(NCONS), x(NDIM)
            real(kind=RP)  :: cos1, sin2
!
!           Usage example (by default no source terms are added)
!           ----------------------------------------------------
!$omp do schedule(runtime) private(i,j,k,x,cos1,sin2,S)
            do eID = 1, mesh % no_of_elements
               associate ( e => mesh % elements(eID) )
               do k = 0, e % Nxyz(3)   ; do j = 0, e % Nxyz(2) ; do i = 0, e % Nxyz(1)
                  x = e % geom % x(:,i,j,k)
                  cos1 = cos(PI * (x(1) + x(2) - 1.0_RP + x(3) - 2.0_RP*time))
                  sin2 = sin(2.0_RP * PI *(x(1) + x(2) - 1.0_RP + x(3) - 2.0_RP*time))

                  S(IRHO)  = c1 * cos1
                  S(IRHOU) = c2 * cos1 + c3 * sin2
                  S(IRHOV) = c2 * cos1 + c3 * sin2
                  S(IRHOW) = c2 * cos1 + c3 * sin2
                  S(IRHOE) = c4 * cos1 + c5 * sin2

                  e % storage % QDot(:,i,j,k) = e % storage % QDot(:,i,j,k) + S
               end do                  ; end do                ; end do
               end associate
            end do
!$omp end do
   
         end subroutine UserDefinedSourceTerm
!
!//////////////////////////////////////////////////////////////////////// 
! 
         SUBROUTINE UserDefinedFinalize(mesh, time, iter, maxResidual, thermodynamics_, &
                                                    dimensionless_, &
                                                        refValues_, &  
                                                          monitors, &
                                                       elapsedTime, &
                                                           CPUTime   )
!
!           --------------------------------------------------------
!           Called after the solution computed to allow, for example
!           error tests to be performed
!           --------------------------------------------------------
!
            USE HexMeshClass
            use PhysicsStorage
            use MonitorsClass
            IMPLICIT NONE
            CLASS(HexMesh)                        :: mesh
            REAL(KIND=RP)                         :: time
            integer                               :: iter
            real(kind=RP)                         :: maxResidual
            type(Thermodynamics_t),    intent(in) :: thermodynamics_
            type(Dimensionless_t),     intent(in) :: dimensionless_
            type(RefValues_t),         intent(in) :: refValues_
            type(Monitor_t),           intent(in) :: monitors
            real(kind=RP),             intent(in) :: elapsedTime
            real(kind=RP),             intent(in) :: CPUTime
!
!           ---------------
!           Local variables
!           ---------------
!
            integer     :: eID, i, j, k, fid
            real(kind=RP)  :: x(NDIM)
            real(kind=RP)  :: L2error, L2local
            real(kind=RP)  :: Qexpected(NCONS)

            L2error = 0.0_RP

            do eID = 1, mesh % no_of_elements
               associate ( e => mesh % elements(eID) ) 
               do k = 0, e % Nxyz(3)   ; do j = 0, e % Nxyz(2)    ; do i = 0, e % Nxyz(1)
                  x = e % geom % x(:,i,j,k)

                  Qexpected(1) = ( 2.0_RP + 0.1_RP * sin(PI*(x(1) + x(2) - 1.0_RP + x(3)- 2.0_RP * time)))
                  Qexpected(2) = Qexpected(1)
                  Qexpected(3) = Qexpected(1)
                  Qexpected(4) = Qexpected(1)
                  Qexpected(5) = POW2(Qexpected(1))

                  L2local = norm2( e % storage % Q(:,i,j,k) - Qexpected )
                  L2error = max(L2local,L2error)
               end do                  ; end do                   ; end do
               end associate
            end do
!
!           Write the results in a file
!           ---------------------------
            open(newunit=fid,file="./RESULTS/BenchResults.out",status="old",access="append",action="write")
            write(fid,*) mesh % no_of_elements, mesh % elements(1) % Nxyz(1), L2error, elapsedTime, CPUTime
            close(fid)

         END SUBROUTINE UserDefinedFinalize
!
!//////////////////////////////////////////////////////////////////////// 
! 
      SUBROUTINE UserDefinedTermination
!
!        -----------------------------------------------
!        Called at the the end of the main driver after 
!        everything else is done.
!        -----------------------------------------------
!
         IMPLICIT NONE  
      END SUBROUTINE UserDefinedTermination
      
