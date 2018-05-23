!
!//////////////////////////////////////////////////////
!
!   @File:    GradientsStabilization.f90
!   @Author:  Juan (juan.manzanero@upm.es)
!   @Created: Thu Apr 12 11:32:49 2018
!   @Last revision date: Fri Apr 13 09:03:25 2018
!   @Last revision author: Juan (juan.manzanero@upm.es)
!   @Last revision commit: 0122ccf4e338290aac81495d4aabdf486b3c6a09
!
!//////////////////////////////////////////////////////
!
#include "Includes.h"
module GradientsStabilization
#if defined(CAHNHILLIARD)
   use SMConstants
   use MeshTypes
   use HexMeshClass
   use PhysicsStorage
   use VariableConversion
   use DGSEMClass, only: BCState_FCN
   implicit none

   private
   public   LambdaEstimator_f

   public   StabilizeGradients

   abstract interface
      subroutine LambdaEstimator_f(mesh, fID, i, j, lambda)
         use SMConstants
         use HexMeshClass
         implicit none
         class(HexMesh),   intent(in)  :: mesh
         integer,          intent(in)  :: fID, i, j
         real(kind=RP),    intent(out) :: lambda
      end subroutine LambdaEstimator_f
   end interface
!
!  ========
   contains
!  ========
!
      subroutine StabilizeGradients(mesh, time, externalStateProcedure)
         implicit none
         class(HexMesh)                :: mesh
         real(kind=RP),    intent(in)  :: time
         procedure(BCState_FCN)        :: externalStateProcedure
!
!        ---------------
!        Local variables
!        ---------------
!
         integer  :: eID, fID, i, j, k
!
!        **************************************************
!        Compute the face stabilization flux in local faces
!        **************************************************
!
!$omp do schedule(runtime) 
         do fID = 1, SIZE(mesh % faces) 
            associate(f => mesh % faces(fID)) 
            select case (f % faceType) 
            case (HMESH_INTERIOR) 
               call GradientsStabilization_InteriorFace(f) 
            
            case (HMESH_BOUNDARY) 
               call GradientsStabilization_BoundaryFace(f, time, externalStateProcedure) 
 
            end select 
            end associate 
         end do            
!$omp end do 
!
!$omp do schedule(runtime) 
         do eID = 1, size(mesh % elements) 
            associate(e => mesh % elements(eID))
#ifdef __HAS_MPI__
            if ( e % hasSharedFaces ) cycle
#endif
!
!           Revert the scaling
!           -------------------               
            do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2)  ; do i = 0, e % Nxyz(1)
               e % storage % U_x(:,i,j,k) = &
                           e % storage % U_x(:,i,j,k) * e % geom % jacobian(i,j,k)
               e % storage % U_y(:,i,j,k) = &
                           e % storage % U_y(:,i,j,k) * e % geom % jacobian(i,j,k)
               e % storage % U_z(:,i,j,k) = &
                           e % storage % U_z(:,i,j,k) * e % geom % jacobian(i,j,k)
            end do         ; end do          ; end do
!
!           Add the surface integrals
!           -------------------------
            call PerformSurfaceIntegrals( e, mesh)
!
!           Perform the scaling
!           -------------------               
            do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2)  ; do i = 0, e % Nxyz(1)
               e % storage % U_x(:,i,j,k) = &
                           e % storage % U_x(:,i,j,k) / e % geom % jacobian(i,j,k)
               e % storage % U_y(:,i,j,k) = &
                           e % storage % U_y(:,i,j,k) / e % geom % jacobian(i,j,k)
               e % storage % U_z(:,i,j,k) = &
                           e % storage % U_z(:,i,j,k) / e % geom % jacobian(i,j,k)
            end do         ; end do          ; end do

            end associate
         end do
!$omp end do

#ifdef __HAS_MPI__
!$omp do schedule(runtime) 
         do fID = 1, SIZE(mesh % faces) 
            associate(f => mesh % faces(fID)) 
            select case (f % faceType) 
            case (HMESH_MPI) 
               call GradientsStabilization_MPIFace(f) 
 
            end select 
            end associate 
         end do            
!$omp end do 
!
!$omp do schedule(runtime) 
         do eID = 1, size(mesh % elements) 
            associate(e => mesh % elements(eID))
            if ( .not. e % hasSharedFaces ) cycle
!
!           Revert the scaling
!           -------------------               
            do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2)  ; do i = 0, e % Nxyz(1)
               e % storage % U_x(:,i,j,k) = &
                           e % storage % U_x(:,i,j,k) * e % geom % jacobian(i,j,k)
               e % storage % U_y(:,i,j,k) = &
                           e % storage % U_y(:,i,j,k) * e % geom % jacobian(i,j,k)
               e % storage % U_z(:,i,j,k) = &
                           e % storage % U_z(:,i,j,k) * e % geom % jacobian(i,j,k)
            end do         ; end do          ; end do

!
!           Add the surface integrals
!           -------------------------
            call PerformSurfaceIntegrals( e, mesh)
!
!           Perform the scaling
!           -------------------               
            do k = 0, e % Nxyz(3) ; do j = 0, e % Nxyz(2)  ; do i = 0, e % Nxyz(1)
               e % storage % U_x(:,i,j,k) = &
                           e % storage % U_x(:,i,j,k) / e % geom % jacobian(i,j,k)
               e % storage % U_y(:,i,j,k) = &
                           e % storage % U_y(:,i,j,k) / e % geom % jacobian(i,j,k)
               e % storage % U_z(:,i,j,k) = &
                           e % storage % U_z(:,i,j,k) / e % geom % jacobian(i,j,k)
            end do         ; end do          ; end do

            end associate
         end do
!$omp end do
#endif

      end subroutine StabilizeGradients

      subroutine GradientsStabilization_InteriorFace(f)
         use Physics  
         use ElementClass
         use FaceClass
         implicit none  
!
!        ---------
!        Arguments
!        ---------
!
         type(Face)    :: f
         procedure(LambdaEstimator_f)  :: LambdaEstimator
!
!        ---------------
!        Local variables
!        ---------------
!
         integer       :: i,j
         real(kind=RP) :: UL(N_GRAD_EQN), UR(N_GRAD_EQN)
         real(kind=RP) :: Uhat(N_GRAD_EQN)
         real(kind=RP) :: Hflux(N_GRAD_EQN,NDIM,0:f % Nf(1), 0:f % Nf(2))
         real(kind=RP) :: vAver(NDIM)
         
         do j = 0, f % Nf(2)  ; do i = 0, f % Nf(1)
            call GradientValuesForQ(Q = f % storage(1) % Q(:,i,j), U = UL)
            call GradientValuesForQ(Q = f % storage(2) % Q(:,i,j), U = UR)
  
            vAver = AVERAGE( f % storage(1) % v(:,i,j) , f % storage(2) % v(:,i,j))

            Uhat = 0.5_RP * sign2(dot_product(vAver, f % geom % normal(:,i,j)))*(UL - UR) * f % geom % jacobian(i,j) 
            Hflux(:,IX,i,j) = Uhat * f % geom % normal(IX,i,j)
            Hflux(:,IY,i,j) = Uhat * f % geom % normal(IY,i,j)
            Hflux(:,IZ,i,j) = Uhat * f % geom % normal(IZ,i,j)
         end do               ; end do

         call f % ProjectGradientFluxToElements(HFlux,(/1,2/),-1)
         
      end subroutine GradientsStabilization_InteriorFace   

      subroutine GradientsStabilization_MPIFace(f)
         use Physics  
         use ElementClass
         use FaceClass
         implicit none  
!
!        ---------
!        Arguments
!        ---------
!
         type(Face)    :: f
!
!        ---------------
!        Local variables
!        ---------------
!
         integer       :: i,j, thisSide
         real(kind=RP) :: UL(N_GRAD_EQN), UR(N_GRAD_EQN)
         real(kind=RP) :: Uhat(N_GRAD_EQN)
         real(kind=RP) :: Hflux(N_GRAD_EQN,NDIM,0:f % Nf(1), 0:f % Nf(2))
         real(kind=RP) :: vAver(NDIM)

         do j = 0, f % Nf(2)  ; do i = 0, f % Nf(1)
            call GradientValuesForQ(Q = f % storage(1) % Q(:,i,j), U = UL)
            call GradientValuesForQ(Q = f % storage(2) % Q(:,i,j), U = UR)
   
            vAver = AVERAGE( f % storage(1) % v(:,i,j) , f % storage(2) % v(:,i,j))

            Uhat = 0.5_RP * sign2(dot_product(vAver, f % geom % normal(:,i,j)))*(UL - UR) * f % geom % jacobian(i,j)
            Hflux(:,IX,i,j) = Uhat * f % geom % normal(IX,i,j)
            Hflux(:,IY,i,j) = Uhat * f % geom % normal(IY,i,j)
            Hflux(:,IZ,i,j) = Uhat * f % geom % normal(IZ,i,j)
         end do               ; end do

         thisSide = maxloc(f % elementIDs, dim = 1)
         call f % ProjectGradientFluxToElements(HFlux,(/thisSide, HMESH_NONE/),-1)
         
      end subroutine GradientsStabilization_MPIFace   

      subroutine GradientsStabilization_BoundaryFace(f, time, externalState)
         use Physics
         use FaceClass
         implicit none
         type(Face)    :: f
         real(kind=RP) :: time
         external      :: externalState
         integer       :: i, j
         real(kind=RP) :: Uhat(N_GRAD_EQN), UL(N_GRAD_EQN), UR(N_GRAD_EQN)
         real(kind=RP) :: bvExt(N_EQN)

         do j = 0, f % Nf(2)  ; do i = 0, f % Nf(1)

            bvExt =  f % storage(1) % Q(:,i,j)
   
            call externalState( f % geom % x(:,i,j), &
                                time               , &
                                f % geom % normal(:,i,j)      , &
                                bvExt              , &
                                f % boundaryType )  
!   
!           -------------------
!           u, v, w, T averages
!           -------------------
!   
            call GradientValuesForQ( f % storage(1) % Q(:,i,j), UL )
            call GradientValuesForQ( bvExt, UR )
   
            Uhat = 0.5_RP * dot_product(f % storage(1) % v(:,i,j), f % geom % normal(:,i,j))*(UL - UR) * f % geom % jacobian(i,j) / (abs(dot_product(f % storage(1) % v(:,i,j),f % geom % normal(:,i,j))) + epsilon(1.0_RP))
            f % storage(1) % unStar(:,1,i,j) = Uhat * f % geom % normal(1,i,j)
            f % storage(1) % unStar(:,2,i,j) = Uhat * f % geom % normal(2,i,j)
            f % storage(1) % unStar(:,3,i,j) = Uhat * f % geom % normal(3,i,j)

         end do ; end do   
         
      end subroutine GradientsStabilization_BoundaryFace

      subroutine PerformSurfaceIntegrals( e, mesh )
         use ElementClass
         use HexMeshClass
         use PhysicsStorage
         use Physics
         use DGIntegrals
         implicit none
         class(Element)                      :: e
         class(HexMesh)                      :: mesh
!
!        ---------------
!        Local variables
!        ---------------
!
         real(kind=RP)        :: faceInt_x(N_GRAD_EQN, 0:e%Nxyz(1) , 0:e%Nxyz(2) , 0:e%Nxyz(3) )
         real(kind=RP)        :: faceInt_y(N_GRAD_EQN, 0:e%Nxyz(1) , 0:e%Nxyz(2) , 0:e%Nxyz(3) )
         real(kind=RP)        :: faceInt_z(N_GRAD_EQN, 0:e%Nxyz(1) , 0:e%Nxyz(2) , 0:e%Nxyz(3) )

         call VectorWeakIntegrals % StdFace(e, &
               mesh % faces(e % faceIDs(EFRONT))  % storage(e % faceSide(EFRONT))  % unStar, &
               mesh % faces(e % faceIDs(EBACK))   % storage(e % faceSide(EBACK))   % unStar, &
               mesh % faces(e % faceIDs(EBOTTOM)) % storage(e % faceSide(EBOTTOM)) % unStar, &
               mesh % faces(e % faceIDs(ERIGHT))  % storage(e % faceSide(ERIGHT))  % unStar, &
               mesh % faces(e % faceIDs(ETOP))    % storage(e % faceSide(ETOP))    % unStar, &
               mesh % faces(e % faceIDs(ELEFT))   % storage(e % faceSide(ELEFT))   % unStar, &
               faceInt_x, faceInt_y, faceInt_z )

         e % storage % U_x = e % storage % U_x + faceInt_x
         e % storage % U_y = e % storage % U_y + faceInt_y
         e % storage % U_z = e % storage % U_z + faceInt_z

      end subroutine PerformSurfaceIntegrals
#endif
end module GradientsStabilization
