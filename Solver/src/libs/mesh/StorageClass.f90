!
!//////////////////////////////////////////////////////
!
!   @File:    StorageClass.f90
!   @Author:  Juan Manzanero (juan.manzanero@upm.es)
!   @Created: Thu Oct  5 09:17:17 2017
!   @Last revision date: Fri Sep  7 19:07:24 2018
!   @Last revision author: Andrés Rueda (am.rueda@upm.es)
!   @Last revision commit: 95cf879e21e49900ff67f23490a18c87162fe91d
!
!//////////////////////////////////////////////////////
!
#include "Includes.h"
module StorageClass
   use, intrinsic :: iso_c_binding
   use SMConstants
   use PhysicsStorage
   use InterpolationMatrices, only: ConstructInterpolationMatrices, Interp3DArrays
   use NodalStorageClass    , only: NodalStorage
   implicit none

   private
   public   ElementStorage_t, FaceStorage_t, SolutionStorage_t
   public   GetStorageEquations
  
   enum, bind(C)
      enumerator :: OFF = 0, NS, C, MU
   end enum 

   type Statistics_t
      real(kind=RP), dimension(:,:,:,:),  allocatable    :: data
      contains
         procedure   :: Construct => Statistics_Construct
         procedure   :: Destruct  => Statistics_Destruct
   end type Statistics_t
   
!  
!  Class for pointing to previous solutions in an element
!  ******************************************************
   type ElementPrevSol_t
#if defined(NAVIERSTOKES) || defined(INCNS)
      real(kind=RP), dimension(:,:,:,:),  allocatable     :: QNS
#endif
#if defined(CAHNHILLIARD)
      real(kind=RP), dimension(:,:,:,:),  allocatable     :: c
#endif
   end type ElementPrevSol_t
!  
!  Class for storing variables element-wise
!     (Q and Qdot are not owned by ElementStorage_t) 
!  ****************************************
   type ElementStorage_t
      integer                                         :: currentlyLoaded
      integer                                         :: NDOF              ! Number of degrees of freedom of element
      integer                                         :: Nxyz(NDIM)
      real(kind=RP), dimension(:,:,:,:),  pointer, contiguous     :: Q           ! Pointers to the appropriate storage (NS or CH)
      real(kind=RP), dimension(:,:,:,:),  pointer, contiguous     :: QDot        !
      real(kind=RP), dimension(:,:,:,:),  pointer, contiguous     :: U_x         !
      real(kind=RP), dimension(:,:,:,:),  pointer, contiguous     :: U_y         !
      real(kind=RP), dimension(:,:,:,:),  pointer, contiguous     :: U_z         !
      type(ElementPrevSol_t),  allocatable :: PrevQ(:)           ! Previous solution
#if defined(NAVIERSTOKES) || defined(INCNS)
      real(kind=RP),           allocatable :: QNS(:,:,:,:)         ! NSE State vector
      real(kind=RP), private,  allocatable :: QDotNS(:,:,:,:)      ! NSE State vector time derivative
      real(kind=RP), private,  allocatable :: U_xNS(:,:,:,:)       ! NSE x-gradients
      real(kind=RP), private,  allocatable :: U_yNS(:,:,:,:)       ! NSE y-gradients
      real(kind=RP), private,  allocatable :: U_zNS(:,:,:,:)       ! NSE z-gradients
      real(kind=RP),           allocatable :: gradRho(:,:,:,:)
      real(kind=RP),           allocatable :: G_NS(:,:,:,:)        ! NSE auxiliar storage
      real(kind=RP),           allocatable :: S_NS(:,:,:,:)        ! NSE source term
      type(Statistics_t)                   :: stats                ! NSE statistics
!
!     Pointers to face Jacobians
!     -> Currently only for df/dq⁺, For off-diagonal blocks, add df/dq⁻
!     ----------------------------------------------------------------
      real(kind=RP), dimension(:,:,:,:), pointer      :: dfdq_fr  ! FRONT
      real(kind=RP), dimension(:,:,:,:), pointer      :: dfdq_ba  ! BACK
      real(kind=RP), dimension(:,:,:,:), pointer      :: dfdq_bo  ! BOTTOM
      real(kind=RP), dimension(:,:,:,:), pointer      :: dfdq_to  ! TOP
      real(kind=RP), dimension(:,:,:,:), pointer      :: dfdq_ri  ! RIGHT
      real(kind=RP), dimension(:,:,:,:), pointer      :: dfdq_le  ! LEFT
      
      real(kind=RP), dimension(:,:,:,:,:,:), pointer    :: dfdGradQ_fr  ! FRONT
      real(kind=RP), dimension(:,:,:,:,:,:), pointer    :: dfdGradQ_ba  ! BACK
      real(kind=RP), dimension(:,:,:,:,:,:), pointer    :: dfdGradQ_bo  ! BOTTOM
      real(kind=RP), dimension(:,:,:,:,:,:), pointer    :: dfdGradQ_to  ! TOP
      real(kind=RP), dimension(:,:,:,:,:,:), pointer    :: dfdGradQ_ri  ! RIGHT
      real(kind=RP), dimension(:,:,:,:,:,:), pointer    :: dfdGradQ_le  ! LEFT
#endif
#if defined(CAHNHILLIARD)
      real(kind=RP), dimension(:,:,:,:),   allocatable :: c     ! CHE concentration
      real(kind=RP), dimension(:,:,:,:),   allocatable :: cDot  ! CHE concentration time derivative
      real(kind=RP), dimension(:,:,:,:),   allocatable :: c_x   ! CHE concentration x-gradient
      real(kind=RP), dimension(:,:,:,:),   allocatable :: c_y   ! CHE concentration y-gradient
      real(kind=RP), dimension(:,:,:,:),   allocatable :: c_z   ! CHE concentration z-gradient
      real(kind=RP), dimension(:,:,:,:),   allocatable :: mu    ! CHE chemical potential
      real(kind=RP), dimension(:,:,:,:),   allocatable :: mu_x  ! CHE chemical potential x-gradient
      real(kind=RP), dimension(:,:,:,:),   allocatable :: mu_y  ! CHE chemical potential y-gradient
      real(kind=RP), dimension(:,:,:,:),   allocatable :: mu_z  ! CHE chemical potential z-gradient
      real(kind=RP), dimension(:,:,:,:),   allocatable :: v     ! CHE flow field velocity
      real(kind=RP), dimension(:,:,:,:),   allocatable :: G_CH  ! CHE auxiliar storage   
#endif
      contains
         procedure   :: Assign              => ElementStorage_Assign
         generic     :: assignment(=)       => Assign
         procedure   :: Construct           => ElementStorage_Construct
         procedure   :: Destruct            => ElementStorage_Destruct
         procedure   :: InterpolateSolution => ElementStorage_InterpolateSolution
#if defined(NAVIERSTOKES) || defined(INCNS)
         procedure   :: SetStorageToNS    => ElementStorage_SetStorageToNS
#endif
#if defined(CAHNHILLIARD)
         procedure   :: SetStorageToCH_c  => ElementStorage_SetStorageToCH_c
         procedure   :: SetStorageToCH_mu => ElementStorage_SetStorageToCH_mu
#endif
   end type ElementStorage_t
   
!  
!  Class for storing variables in the whole domain
!  ***********************************************
   type SolutionStorage_t
      integer                                    :: NDOF
      logical                                    :: AdaptedQ     = .FALSE.
      logical                                    :: AdaptedQdot  = .FALSE.
      logical                                    :: AdaptedPrevQ = .FALSE.
      integer                                    :: prevSol_num    = 0
      integer                      , allocatable :: prevSol_index(:)           ! Indexes for the previous solutions
      
      type(ElementStorage_t)       , allocatable :: elements(:)
      real(kind=RP),                 pointer     :: Q(:)
      real(kind=RP),                 pointer     :: QDot(:)
      real(kind=RP),                 pointer     :: PrevQ(:,:)
#if defined(NAVIERSTOKES) || defined(INCNS)
      real(kind=RP), dimension(:)  , allocatable :: QdotNS
      real(kind=RP), dimension(:)  , allocatable :: QNS
      real(kind=RP), dimension(:,:), allocatable :: PrevQNS ! Previous solution(s) in the whole domain
#endif
#if defined(CAHNHILLIARD)
      real(kind=RP), dimension(:)  , allocatable :: cDot
      real(kind=RP), dimension(:)  , allocatable :: c
      real(kind=RP), dimension(:,:), allocatable :: Prevc(:,:)
#endif      
      contains
         procedure :: construct        => SolutionStorage_Construct
         procedure :: local2GlobalQ    => SolutionStorage_local2GlobalQ
         procedure :: local2GlobalQdot => SolutionStorage_local2GlobalQdot
         procedure :: SetGlobalPrevQ   => SolutionStorage_SetGlobalPrevQ
         procedure :: global2LocalQ    => SolutionStorage_global2LocalQ
         procedure :: global2LocalQdot => SolutionStorage_global2LocalQdot
         procedure :: Destruct         => SolutionStorage_Destruct
         procedure :: SignalAdaptation => SolutionStorage_SignalAdaptation
   end type SolutionStorage_t
!  
!  Class for storing variables in the faces
!  ****************************************
   type FaceStorage_t
      integer                                          :: currentlyLoaded
      integer                                          :: Nf(2), Nel(2)
      real(kind=RP), dimension(:,:,:),     pointer     :: Q
      real(kind=RP), dimension(:,:,:),     pointer     :: U_x, U_y, U_z
      real(kind=RP), dimension(:,:,:),     pointer     :: FStar
      real(kind=RP), dimension(:,:,:,:),   pointer     :: unStar
      real(kind=RP), dimension(:),         allocatable :: genericInterfaceFluxMemory ! unStar and fStar point to this memory simultaneously. This seems safe.
#if defined(NAVIERSTOKES) || defined(INCNS)
      real(kind=RP), dimension(:,:,:),     allocatable :: QNS
      real(kind=RP), dimension(:,:,:),     allocatable :: U_xNS, U_yNS, U_zNS
      real(kind=RP), dimension(:,:,:),     allocatable :: gradRho          ! Gradient of density
      ! Inviscid Jacobians
      real(kind=RP), dimension(:,:,:,:)  , allocatable :: dFStar_dqF   ! In storage(1), it stores dFStar/dqL, and in storage(2), it stores dFStar/dqR on the mortar points
      real(kind=RP), dimension(:,:,:,:,:), allocatable :: dFStar_dqEl  ! Stores both dFStar/dqL and dFStar/dqR on the face-element points of the corresponding side
      ! Viscous Jacobians
      real(kind=RP), dimension(:,:,:,:,:,:), allocatable :: dFv_dGradQF  ! In storage(1), it stores dFv*/d∇qL, and in storage(2), it stores dFv*/d∇qR on the mortar points
      real(kind=RP), dimension(:,:,:,:,:,:), allocatable :: dFv_dGradQEl ! In storage(1), it stores dFv*/d∇qL, and in storage(2), it stores dFv*/d∇qR on the face-element points ... NOTE: this is enough for the diagonal blocks of the Jacobian, for off-diagonal blocks the crossed quantities must be computed and stored
#endif
#if defined(CAHNHILLIARD)
      real(kind=RP), dimension(:,:,:),   allocatable :: c
      real(kind=RP), dimension(:,:,:),   allocatable :: c_x
      real(kind=RP), dimension(:,:,:),   allocatable :: c_y
      real(kind=RP), dimension(:,:,:),   allocatable :: c_z
      real(kind=RP), dimension(:,:,:),   allocatable :: mu
      real(kind=RP), dimension(:,:,:),   allocatable :: mu_x
      real(kind=RP), dimension(:,:,:),   allocatable :: mu_y
      real(kind=RP), dimension(:,:,:),   allocatable :: mu_z
      real(kind=RP), dimension(:,:,:),   allocatable :: v
#endif
      contains
         procedure   :: Construct => FaceStorage_Construct
         procedure   :: Destruct  => FaceStorage_Destruct
#if defined(NAVIERSTOKES) || defined(INCNS)
         procedure   :: SetStorageToNS => FaceStorage_SetStorageToNS
#endif
#if defined(CAHNHILLIARD)
         procedure   :: SetStorageToCH_c  => FaceStorage_SetStorageToCH_c
         procedure   :: SetStorageToCH_mu => FaceStorage_SetStorageToCH_mu
#endif
   end type FaceStorage_t
!
!  ========
   contains
!  ========
!
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!           Global Storage procedures
!           --------------------------
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!     -------------------------------------------------------
!     The global solution arrays are only allocated if needed
!     -------------------------------------------------------
      pure subroutine SolutionStorage_Construct(self, NDOF, Nx, Ny, Nz, computeGradients, prevSol_num)
         implicit none
         !-arguments---------------------------------------------
         class(SolutionStorage_t), target, intent(inout) :: self
         integer                 , intent(in)    :: NDOF
         integer, dimension(:)   , intent(in)    :: Nx, Ny, Nz
         logical                 , intent(in)    :: computeGradients                   !<  Compute gradients?
         integer, optional       , intent(in)    :: prevSol_num
         !-local-variables---------------------------------------
         integer :: k
         !-------------------------------------------------------
         
         self % NDOF = NDOF
         
         if ( present(prevSol_num) ) then 
            if ( prevSol_num > 0 ) then
               self % prevSol_num = prevSol_num
               allocate ( self % prevSol_index(prevSol_num) )
               self % prevSol_index = (/ (k, k=1, prevSol_num) /)
            end if
         end if
         
         allocate (self % elements(size(Nx)) )
         call self % elements % construct( Nx, Ny, Nz, computeGradients, prevSol_num)
         
      end subroutine SolutionStorage_Construct
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!     --------------------------------------------
!     Load the local solutions into a global array
!     --------------------------------------------
      pure subroutine SolutionStorage_local2GlobalQ(self, NDOF)
         implicit none
         !----------------------------------------------
         class(SolutionStorage_t), target, intent(inout) :: self
         integer                 , intent(in)    :: NDOF
         !----------------------------------------------
         integer :: firstIdx, lastIdx, eID
         !----------------------------------------------
         
!        Allocate storage
!        ****************
#if defined(NAVIERSTOKES)
         if (self % AdaptedQ .or. (.not. allocated(self % QNS) ) ) then
            self % NDOF = NDOF
            safedeallocate (self % QNS   )
            allocate ( self % QNS   (NCONS*NDOF) )
            
            self % Q    => self % QNS
            self % AdaptedQ = .FALSE.
         end if
#elif defined(INCNS)
         if (self % AdaptedQ .or. (.not. allocated(self % QNS) ) ) then
            self % NDOF = NDOF
            safedeallocate (self % QNS   )
            allocate ( self % QNS   (NINC*NDOF) )
            
            self % Q => self % QNS
            self % AdaptedQ = .FALSE.
         end if
#endif
#if defined(CAHNHILLIARD)
         if (self % AdaptedQ .or. (.not. allocated(self % c) ) ) then
            self % NDOF = NDOF
            safedeallocate (self % c)
            allocate ( self % c(NCOMP*NDOF) )
            
            self % Q => self % c
            self % AdaptedQ = .FALSE.
         end if
#endif
!
!        Load solution
!        *************
         
#if defined(NAVIERSTOKES)
         firstIdx = 1
         do eID=1, size(self % elements)
            lastIdx = firstIdx + self % elements(eID) % NDOF * NCONS
            self % QNS (firstIdx : lastIdx - 1) = reshape ( self % elements(eID) % QNS , (/ self % elements(eID) % NDOF *NCONS /) )
            firstIdx = lastIdx
         end do
#elif defined(INCNS)
         firstIdx = 1
         do eID=1, size(self % elements)
            lastIdx = firstIdx + self % elements(eID) % NDOF * NINC
            self % QNS (firstIdx : lastIdx - 1) = reshape ( self % elements(eID) % QNS , (/ self % elements(eID) % NDOF *NINC /) )
            firstIdx = lastIdx
         end do
#endif
#if defined(CAHNHILLIARD)
         firstIdx = 1
         do eID=1, size(self % elements)
            lastIdx = firstIdx + self % elements(eID) % NDOF * NCOMP
            self % c (firstIdx : lastIdx - 1) = reshape ( self % elements(eID) % c , (/ self % elements(eID) % NDOF *NCOMP /) )
            firstIdx = lastIdx
         end do
#endif
         
      end subroutine SolutionStorage_local2GlobalQ
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!     ---------------------------------------
!     Load the local Qdot into a global array
!     ---------------------------------------
      pure subroutine SolutionStorage_local2GlobalQdot(self, NDOF)
         implicit none
         !----------------------------------------------
         class(SolutionStorage_t), target, intent(inout) :: self
         integer                 , intent(in)    :: NDOF
         !----------------------------------------------
         integer :: firstIdx, lastIdx, eID
         !----------------------------------------------
         
         self % NDOF = NDOF
         
#if defined(NAVIERSTOKES)
         if (self % AdaptedQdot .or. (.not. allocated(self % QdotNS) ) ) then
            safedeallocate (self % QdotNS)
            allocate ( self % QdotNS(NCONS*NDOF) )
            self % QDot => self % QDotNS
         end if
#elif defined(INCNS)
         if (self % AdaptedQdot .or. (.not. allocated(self % QdotNS) ) ) then
            safedeallocate (self % QdotNS)
            allocate ( self % QdotNS(NINC*NDOF) )
            self % QDot => self % QDotNS
         end if
#endif
#if defined(CAHNHILLIARD)
         if (self % AdaptedQdot .or. (.not. allocated(self % cDot) ) ) then
            safedeallocate ( self % cDot )
            allocate ( self % cDot(NCOMP*NDOF) )
            self % QDot => self % cDot
         end if
#endif
         self % AdaptedQdot = .FALSE.
         
!
!        Load solution
!        *************
         
#if defined(NAVIERSTOKES)
         firstIdx = 1
         do eID=1, size(self % elements)
            lastIdx = firstIdx + self % elements(eID) % NDOF * NCONS
            self % QdotNS (firstIdx : lastIdx - 1) = reshape ( self % elements(eID) % QdotNS , (/ self % elements(eID) % NDOF * NCONS/) )
            firstIdx = lastIdx
         end do
#elif defined(INCNS)
         firstIdx = 1
         do eID=1, size(self % elements)
            lastIdx = firstIdx + self % elements(eID) % NDOF * NINC
            self % QdotNS (firstIdx : lastIdx - 1) = reshape ( self % elements(eID) % QdotNS , (/ self % elements(eID) % NDOF * NINC /) )
            firstIdx = lastIdx
         end do
#endif
#if defined(CAHNHILLIARD)
         firstIdx = 1
         do eID=1, size(self % elements)
            lastIdx = firstIdx + self % elements(eID) % NDOF * NCOMP
            self % cDot (firstIdx : lastIdx - 1) = reshape ( self % elements(eID) % cDot , (/ self % elements(eID) % NDOF * NCOMP /) )
            firstIdx = lastIdx
         end do
#endif
      end subroutine SolutionStorage_local2GlobalQdot
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!     --------------------------------------------
!     Load the local solutions into a global array
!     --------------------------------------------
      pure subroutine SolutionStorage_SetGlobalPrevQ(self, Q)
         implicit none
         !-arguments---------------------------------------------
         class(SolutionStorage_t), target, intent(inout) :: self
         real(kind=RP)                   , intent(in)    :: Q(:)
         !-local-variables---------------------------------------
         integer :: k, oldest_index
         !-------------------------------------------------------
         
         if (self % prevSol_num < 1) return
         
!        Allocate global storage
!        ***********************
#if defined(NAVIERSTOKES)
         if (self % AdaptedPrevQ .or. (.not. allocated(self % PrevQNS) ) ) then
            safedeallocate (self % PrevQNS)
            allocate ( self % PrevQNS (NCONS * self % NDOF, self % prevSol_num) )
            
            self % PrevQ => self % PrevQNS
            self % AdaptedPrevQ = .FALSE.
            
            ! TODO: Adapt previous solutions...
         end if
#elif defined(INCNS)
         if (self % AdaptedPrevQ .or. (.not. allocated(self % PrevQNS) ) ) then
            safedeallocate (self % PrevQNS)
            allocate ( self % PrevQNS (NINC * self % NDOF, self % prevSol_num) )
            
            self % PrevQ => self % PrevQNS
            self % AdaptedPrevQ = .FALSE.
            
            ! TODO: Adapt previous solutions...
         end if
#endif
#if defined(CAHNHILLIARD)
         if (self % AdaptedPrevQ .or. (.not. allocated(self % PrevC) ) ) then
            safedeallocate (self % PrevC)
            allocate ( self % PrevC(NCOMP * self % NDOF, self % prevSol_num) )
            
            self % AdaptedPrevQ = .FALSE.
            
            ! TODO: Adapt previous solutions...
         end if
#endif
         
!
!        Load solutions
!        **************
         
         oldest_index = self % prevSol_index ( self % prevSol_num )
         do k=self % prevSol_num, 2, -1
            self % prevSol_index(k) = self % prevSol_index(k-1)
         end do
         self % prevSol_index(1) = oldest_index
         
         self % PrevQ (:,self % prevSol_index(1)) = Q
         
      end subroutine SolutionStorage_SetGlobalPrevQ
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
      pure subroutine SolutionStorage_global2LocalQ(self)
         implicit none
         !----------------------------------------------
         class(SolutionStorage_t), target, intent(inout)    :: self
         !----------------------------------------------
         integer :: firstIdx, lastIdx, eID
         !----------------------------------------------      
#if defined(NAVIERSTOKES)
         firstIdx = 1
         do eID=1, size(self % elements)
            associate ( N => self % elements(eID) % Nxyz )
            lastIdx = firstIdx + self % elements(eID) % NDOF * NCONS
            self % elements(eID) % QNS(1:NCONS,0:N(1),0:N(2),0:N(3)) = reshape ( self % QNS (firstIdx:lastIdx-1) , (/ NCONS, N(1)+1, N(2)+1, N(3)+1/) )
            firstIdx = lastIdx
            end associate
         end do
#elif defined(INCNS)
         firstIdx = 1
         do eID=1, size(self % elements)
            associate ( N => self % elements(eID) % Nxyz )
            lastIdx = firstIdx + self % elements(eID) % NDOF * NINC
            self % elements(eID) % QNS(1:NINC,0:N(1),0:N(2),0:N(3)) = reshape ( self % QNS (firstIdx : lastIdx - 1) , (/ NINC, N(1)+1, N(2)+1, N(3)+1/) )
            firstIdx = lastIdx
            end associate
         end do
#endif
#if defined(CAHNHILLIARD)
         firstIdx = 1
         do eID=1, size(self % elements)
            associate ( N => self % elements(eID) % Nxyz )
            lastIdx = firstIdx + self % elements(eID) % NDOF * NCOMP
            self % elements(eID) % c(1:NCOMP,0:N(1),0:N(2),0:N(3)) = reshape ( self % c (firstIdx : lastIdx - 1) , (/ NCOMP, N(1)+1, N(2)+1, N(3)+1/) )
            firstIdx = lastIdx
            end associate
         end do
#endif
      end subroutine SolutionStorage_global2LocalQ
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
      pure subroutine SolutionStorage_global2LocalQdot(self)
         implicit none
         !----------------------------------------------
         class(SolutionStorage_t), target, intent(inout) :: self
         !----------------------------------------------
         integer :: firstIdx, lastIdx, eID
         !----------------------------------------------      
#if defined(NAVIERSTOKES)
         firstIdx = 1
         do eID=1, size(self % elements)
            associate ( N => self % elements(eID) % Nxyz )
            lastIdx = firstIdx + self % elements(eID) % NDOF * NCONS
            self % elements(eID) % QdotNS(1:NCONS,0:N(1),0:N(2),0:N(3)) = reshape ( self % QdotNS (firstIdx:lastIdx-1) , (/ NCONS, N(1)+1, N(2)+1, N(3)+1/) )
            firstIdx = lastIdx
            end associate
         end do
#elif defined(INCNS)
         firstIdx = 1
         do eID=1, size(self % elements)
            associate ( N => self % elements(eID) % Nxyz )
            lastIdx = firstIdx + self % elements(eID) % NDOF * NINC
            self % elements(eID) % QdotNS(1:NINC,0:N(1),0:N(2),0:N(3)) = reshape ( self % QdotNS (firstIdx : lastIdx - 1) , (/ NINC, N(1)+1, N(2)+1, N(3)+1/) )
            firstIdx = lastIdx
            end associate
         end do
#endif
#if defined(CAHNHILLIARD)
         firstIdx = 1
         do eID=1, size(self % elements)
            associate ( N => self % elements(eID) % Nxyz )
            lastIdx = firstIdx + self % elements(eID) % NDOF * NCOMP
            self % elements(eID) % cDot(1:NCOMP,0:N(1),0:N(2),0:N(3)) = reshape ( self % cDot (firstIdx : lastIdx - 1) , (/ NCOMP, N(1)+1, N(2)+1, N(3)+1/) )
            firstIdx = lastIdx
            end associate
         end do
#endif
      end subroutine SolutionStorage_global2LocalQdot
!
!/////////////////////////////////////////////////
!
      pure subroutine SolutionStorage_SignalAdaptation(self)
         implicit none
         class(SolutionStorage_t), intent(inout) :: self
         
         self % AdaptedQ     = .TRUE.
         self % AdaptedQdot  = .TRUE.
         self % AdaptedPrevQ = .TRUE.
      end subroutine SolutionStorage_SignalAdaptation
!
!/////////////////////////////////////////////////
!
      pure subroutine SolutionStorage_Destruct(self)
         implicit none
         class(SolutionStorage_t), intent(inout) :: self
         
         self % prevSol_num = 0
         self % AdaptedQ     = .FALSE.
         self % AdaptedQdot  = .FALSE.
         self % AdaptedPrevQ = .FALSE.
         
         safedeallocate(self % prevSol_index)
         
#if defined(NAVIERSTOKES) || defined(INCNS)
         safedeallocate(self % QNS)
         safedeallocate(self % QdotNS)
         safedeallocate(self % PrevQNS)
#endif
#if defined(CAHNHILLIARD)
         safedeallocate(self % c)
         safedeallocate(self % cDot)
         safedeallocate(self % PrevC)
#endif

         call self % elements % destruct
         deallocate (self % elements)
      end subroutine SolutionStorage_Destruct
!
!///////////////////////////////////////////////////////////////////////////////////////////
!
!           Element Storage procedures
!           --------------------------
!
!///////////////////////////////////////////////////////////////////////////////////////////
!
      elemental subroutine ElementStorage_Construct(self, Nx, Ny, Nz, computeGradients, prevSol_num)
         implicit none
         !------------------------------------------------------------
         class(ElementStorage_t), intent(inout) :: self                               !<> Storage to be constructed
         integer                , intent(in)    :: Nx, Ny, Nz                         !<  Polynomial orders in every direction
         logical                , intent(in)    :: computeGradients                   !<  Compute gradients?
         integer                , intent(in)    :: prevSol_num
         !------------------------------------------------------------
         integer :: k
         integer :: NNS, NGRADNS
         !------------------------------------------------------------
!
!        --------------------------------
!        Get number of degrees of freedom
!        --------------------------------
!
         self % NDOF = (Nx + 1) * (Ny + 1) * (Nz + 1)
         self % Nxyz = [Nx, Ny, Nz]
!
!        ----------------
!        Volume variables
!        ----------------
!
#if defined(NAVIERSTOKES)
         NNS = NCONS
         NGRADNS = NGRAD

#elif defined(INCNS)
         NNS = NINC
         NGRADNS = NINC

#endif 

#if defined(NAVIERSTOKES) || defined(INCNS)
         allocate ( self % QNS   (1:NNS,0:Nx,0:Ny,0:Nz) )
         allocate ( self % QdotNS(1:NNS,0:Nx,0:Ny,0:Nz) )
         ! Previous solution
         if ( prevSol_num /= 0 ) then
            allocate ( self % PrevQ(prevSol_num) )
            do k=1, prevSol_num
               allocate ( self % PrevQ(k) % QNS(1:NNS,0:Nx,0:Ny,0:Nz) )
            end do
         end if

         ALLOCATE( self % G_NS   (NNS,0:Nx,0:Ny,0:Nz) )
         ALLOCATE( self % S_NS   (NNS,0:Nx,0:Ny,0:Nz) )
         
         ALLOCATE( self % U_xNS (NGRADNS,0:Nx,0:Ny,0:Nz) )
         ALLOCATE( self % U_yNS (NGRADNS,0:Nx,0:Ny,0:Nz) )
         ALLOCATE( self % U_zNS (NGRADNS,0:Nx,0:Ny,0:Nz) )
         allocate( self % gradRho(NDIM,0:Nx,0:Ny,0:Nz) )
!
!        Point to NS by default
!        ----------------------
         call self % SetStorageToNS
#endif

#if defined(CAHNHILLIARD)
         allocate ( self % c   (1:NCOMP,0:Nx,0:Ny,0:Nz) )
         allocate ( self % cDot(1:NCOMP,0:Nx,0:Ny,0:Nz) )
         ! Previous solution
         if ( prevSol_num /= 0 ) then
            if ( .not. allocated(self % PrevQ)) then
               allocate ( self % PrevQ(prevSol_num) )
            end if
         end if

         do k=1, prevSol_num
            allocate ( self % PrevQ(k) % c(1:NCOMP,0:Nx,0:Ny,0:Nz) ) 
         end do

         allocate(self % c_x (NCOMP, 0:Nx, 0:Ny, 0:Nz))
         allocate(self % c_y (NCOMP, 0:Nx, 0:Ny, 0:Nz))
         allocate(self % c_z (NCOMP, 0:Nx, 0:Ny, 0:Nz))
         allocate(self % mu  (NCOMP, 0:Nx, 0:Ny, 0:Nz))
         allocate(self % mu_x(NCOMP, 0:Nx, 0:Ny, 0:Nz))
         allocate(self % mu_y(NCOMP, 0:Nx, 0:Ny, 0:Nz))
         allocate(self % mu_z(NCOMP, 0:Nx, 0:Ny, 0:Nz))
         ALLOCATE(self % G_CH(NCOMP,0:Nx,0:Ny,0:Nz) )
         allocate(self % v   (1:NDIM, 0:Nx, 0:Ny, 0:Nz))
#endif
!         
!        -----------------
!        Initialize memory
!        -----------------
!
#if defined(NAVIERSTOKES) || defined(INCNS)
         self % G_NS   = 0.0_RP
         self % S_NS   = 0.0_RP
         self % QNS    = 0.0_RP
         self % QDotNS = 0.0_RP
         
         self % U_xNS = 0.0_RP
         self % U_yNS = 0.0_RP
         self % U_zNS = 0.0_RP
#endif

#if defined(CAHNHILLIARD)
         self % c     = 0.0_RP
         self % c_x   = 0.0_RP
         self % c_y   = 0.0_RP
         self % c_z   = 0.0_RP
         self % mu    = 0.0_RP
         self % mu_x  = 0.0_RP
         self % mu_y  = 0.0_RP
         self % mu_z  = 0.0_RP
         self % G_CH  = 0.0_RP
         self % v     = 0.0_RP
#endif
      
      end subroutine ElementStorage_Construct

      subroutine ElementStorage_Assign(to, from)
!
!        ***********************************
!        We need an special assign procedure
!        ***********************************
!
         implicit none
         class(ElementStorage_t), intent(inout) :: to
         type(ElementStorage_t),  intent(in)    :: from
!
!        Copy the storage
!        ----------------
#if defined(NAVIERSTOKES) || defined(INCNS)
         to % QNS    = from % QNS
         to % U_xNS  = from % U_xNS
         to % U_yNS  = from % U_yNS
         to % U_zNS  = from % U_zNS
         to % QDotNS = from % QDotNS
         to % G_NS   = from % G_NS
#endif
#if defined(CAHNHILLIARD)
         to % c    = from % c
         to % c_x  = from % c_x
         to % c_y  = from % c_y
         to % c_z  = from % c_z
         to % mu   = from % mu
         to % mu_x = from % mu_x
         to % mu_y = from % mu_y
         to % mu_z = from % mu_z
         to % v    = from % v
         to % cDot = from % cDot
         to % G_CH = from % G_CH
#endif

         select case ( to % currentlyLoaded ) 
         case (OFF)
            to % Q    => NULL()
            to % U_x  => NULL()
            to % U_y  => NULL()
            to % U_z  => NULL()
            to % QDot => NULL()

#if defined(NAVIERSTOKES) || defined(INCNS)
         case (NS)
            call to % SetStorageToNS   
#endif
#if defined(CAHNHILLIARD)
         case (C)
            call to % SetStorageToCH_c

         case (MU)
            call to % SetStorageToCH_mu
#endif
         end select

      end subroutine ElementStorage_Assign
!
!///////////////////////////////////////////////////////////////////////////////////////////
!
      elemental subroutine ElementStorage_Destruct(self)
         implicit none
         class(ElementStorage_t), intent(inout) :: self
         integer                 :: num_prevSol, k

         self % currentlyLoaded = OFF
         self % NDOF = 0
         
         self % Q => NULL()
         self % QDot => NULL()
         self % U_x => NULL()
         self % U_y => NULL()
         self % U_z => NULL()

#if defined(NAVIERSTOKES) || defined(INCNS)
         safedeallocate(self % QNS)
         safedeallocate(self % QDotNS)
         
         if ( allocated(self % PrevQ) ) then
            num_prevSol = size(self % PrevQ)
            do k=1, num_prevSol
               safedeallocate( self % PrevQ(k) % QNS )
            end do
         end if
         
         safedeallocate(self % G_NS)
         safedeallocate(self % S_NS)
         safedeallocate(self % U_xNS)
         safedeallocate(self % U_yNS)
         safedeallocate(self % U_zNS)
         safedeallocate(self % gradRho)
         
         nullify ( self % dfdq_fr )
         nullify ( self % dfdq_ba )
         nullify ( self % dfdq_bo )
         nullify ( self % dfdq_to )
         nullify ( self % dfdq_ri )
         nullify ( self % dfdq_le )
         
         nullify ( self % dfdGradQ_fr )
         nullify ( self % dfdGradQ_ba )
         nullify ( self % dfdGradQ_bo )
         nullify ( self % dfdGradQ_to )
         nullify ( self % dfdGradQ_ri )
         nullify ( self % dfdGradQ_le )
#endif
#if defined(CAHNHILLIARD)
         safedeallocate(self % c)
         safedeallocate(self % cDot)
         
         if ( allocated(self % PrevQ) ) then
            num_prevSol = size(self % PrevQ)
            do k=1, num_prevSol
               safedeallocate( self % PrevQ(k) % c )
            end do
         end if
         
         safedeallocate(self % c_x)
         safedeallocate(self % c_y)
         safedeallocate(self % c_z)
         safedeallocate(self % mu)
         safedeallocate(self % mu_x)
         safedeallocate(self % mu_y)
         safedeallocate(self % mu_z)
         safedeallocate(self % G_CH)
         safedeallocate(self % v)
#endif
         safedeallocate(self % PrevQ)

      end subroutine ElementStorage_Destruct
#if defined(NAVIERSTOKES) || defined(INCNS)
      pure subroutine ElementStorage_SetStorageToNS(self)
!
!        *****************************************
!        This subroutine selects the Navier-Stokes
!        state vector as current storage.
!        *****************************************
!
         implicit none
         class(ElementStorage_t), target, intent(inout) :: self

         self % currentlyLoaded = NS
         self % Q   (1:,0:,0:,0:) => self % QNS
         self % U_x (1:,0:,0:,0:) => self % U_xNS
         self % U_y (1:,0:,0:,0:) => self % U_yNS
         self % U_z (1:,0:,0:,0:) => self % U_zNS
         self % QDot(1:,0:,0:,0:) => self % QDotNS

      end subroutine ElementStorage_SetStorageToNS
#endif
#if defined(CAHNHILLIARD)
      pure subroutine ElementStorage_SetStorageToCH_c(self)
!
!        *********************************************
!        This subroutine selects the concentration as
!        current storage.
!        *********************************************
!
         implicit none
         class(ElementStorage_t), target, intent(inout) :: self
      
         self % currentlyLoaded = C
!
!        Point to the one dimensional pointers with generic arrays
!        ---------------------------------------------------------
         self % Q   (1:,0:,0:,0:) => self % c
         self % U_x (1:,0:,0:,0:) => self % c_x
         self % U_y (1:,0:,0:,0:) => self % c_y
         self % U_z (1:,0:,0:,0:) => self % c_z
         self % QDot(1:,0:,0:,0:) => self % cDot
   
      end subroutine ElementStorage_SetStorageToCH_c

      pure subroutine ElementStorage_SetStorageToCH_mu(self)
!
!        *************************************************
!        This subroutine selects the chemical potential as
!        current storage, with the particularity that
!        selects also cDot as QDot.
!        *************************************************
!
         implicit none
         class(ElementStorage_t), target, intent(inout) :: self

         self % currentlyLoaded = MU

         self % Q   (1:,0:,0:,0:) => self % mu
         self % U_x (1:,0:,0:,0:) => self % mu_x
         self % U_y (1:,0:,0:,0:) => self % mu_y
         self % U_z (1:,0:,0:,0:) => self % mu_z
         self % QDot(1:,0:,0:,0:) => self % cDot
   
      end subroutine ElementStorage_SetStorageToCH_mu
#endif
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!     -----------------------------------------------
!     Interpolate solution to another element storage
!            this % Q  ->  other % Q
!     -----------------------------------------------
      impure elemental subroutine ElementStorage_InterpolateSolution(this,other,nodes,with_gradients)
         implicit none
         !-arguments----------------------------------------------
         class(ElementStorage_t), intent(in)    :: this
         type(ElementStorage_t) , intent(inout) :: other
         integer                , intent(in)    :: nodes
         logical, optional      , intent(in)    :: with_gradients
         !-local-variables----------------------------------------
         logical                       :: gradients
         !--------------------------------------------------------
#if defined(NAVIERSTOKES)
         if ( present(with_gradients) ) then
            gradients = with_gradients
         else
            gradients = .FALSE.
         end if
         
         ! Copy the solution if the polynomial orders are the same, if not, interpolate
         if (all(this % Nxyz == other % Nxyz)) then
            other % Q = this % Q
         else
!$omp critical
            call NodalStorage(this  % Nxyz(1)) % construct(nodes,this  % Nxyz(1))
            call NodalStorage(this  % Nxyz(2)) % construct(nodes,this  % Nxyz(2))
            call NodalStorage(this  % Nxyz(3)) % construct(nodes,this  % Nxyz(3))
            call NodalStorage(other % Nxyz(1)) % construct(nodes,other % Nxyz(1))
            call NodalStorage(other % Nxyz(2)) % construct(nodes,other % Nxyz(2))
            call NodalStorage(other % Nxyz(3)) % construct(nodes,other % Nxyz(3))
            !------------------------------------------------------------------
            ! Construct the interpolation matrices in every direction if needed
            !------------------------------------------------------------------
            call ConstructInterpolationMatrices( this % Nxyz(1), other % Nxyz(1) )  ! Xi
            call ConstructInterpolationMatrices( this % Nxyz(2), other % Nxyz(2) )  ! Eta
            call ConstructInterpolationMatrices( this % Nxyz(3), other % Nxyz(3) )  ! Zeta
!$omp end critical
            
            !---------------------------------------------
            ! Interpolate solution to new solution storage
            !---------------------------------------------
            call Interp3DArrays  (Nvars      = NTOTALVARS   , &
                                  Nin        = this  % Nxyz , &
                                  inArray    = this  % Q    , &
                                  Nout       = other % Nxyz , &
                                  outArray   = other % Q    )
            
            if (gradients) then
               call Interp3DArrays  (Nvars      = NTOTALGRADS  , &
                                     Nin        = this % Nxyz  , &
                                     inArray    = this % U_x   , &
                                     Nout       = other % Nxyz , &
                                     outArray   = other % U_x  )
               
               call Interp3DArrays  (Nvars      = NTOTALGRADS  , &
                                     Nin        = this  % Nxyz , &
                                     inArray    = this  % U_y  , &
                                     Nout       = other % Nxyz , &
                                     outArray   = other % U_y  )
                                  
               call Interp3DArrays  (Nvars      = NTOTALGRADS  , &
                                     Nin        = this  % Nxyz , &
                                     inArray    = this  % U_z  , &
                                     Nout       = other % Nxyz , &
                                     outArray   = other % U_z  )
            end if
            
         end if
#endif
      end subroutine ElementStorage_InterpolateSolution
!
!////////////////////////////////////////////////////////////////////////////////////////////
!
!        Face storage procedures
!        -----------------------
!
!////////////////////////////////////////////////////////////////////////////////////////////
!
      subroutine FaceStorage_Construct(self, NDIM, Nf, Nel, computeGradients)
         implicit none
         class(FaceStorage_t)     :: self
         integer, intent(in)  :: NDIM
         integer, intent(in)  :: Nf(2)              ! Face polynomial order
         integer, intent(in)  :: Nel(2)             ! Element face polynomial order
         logical              :: computeGradients 
!
!        ---------------
!        Local variables
!        ---------------
!
         integer     :: interfaceFluxMemorySize
         integer     :: NNS, NGRADNS

         self % Nf  = Nf
         self % Nel = Nel

         interfaceFluxMemorySize = 0

#if defined(NAVIERSTOKES)
         NNS = NCONS
         NGRADNS = NGRAD
#elif defined(INCNS)
         NNS = NINC
         NGRADNS = NINC
#endif
   

#if defined(NAVIERSTOKES) || defined(INCNS)
         ALLOCATE( self % QNS   (NNS,0:Nf(1),0:Nf(2)) )
         ALLOCATE( self % U_xNS(NGRADNS,0:Nf(1),0:Nf(2)) )
         ALLOCATE( self % U_yNS(NGRADNS,0:Nf(1),0:Nf(2)) )
         ALLOCATE( self % U_zNS(NGRADNS,0:Nf(1),0:Nf(2)) )
!
!        Biggest Interface flux memory size is u\vec{n}
!        ----------------------------------------------
         interfaceFluxMemorySize = NGRADNS * nDIM * product(Nf + 1)
!
!        TODO: JMT, if (implicit..?)
         allocate( self % dFStar_dqF (NNS,NNS, 0: Nf(1), 0: Nf(2)) )
         allocate( self % dFStar_dqEl(NNS,NNS, 0:Nel(1), 0:Nel(2),2) )
         
         allocate( self % dFv_dGradQF (NNS,NNS,NDIM,2,0: Nf(1),0: Nf(2)) )
         allocate( self % dFv_dGradQEl(NNS,NNS,NDIM,2,0:Nel(1),0:Nel(2)) )
         
         allocate( self % gradRho   (NDIM,0:Nf(1),0:Nf(2)) )
#endif
#if defined(CAHNHILLIARD)
         allocate(self % c   (NCOMP , 0:Nf(1), 0:Nf(2)))
         allocate(self % c_x (NCOMP , 0:Nf(1), 0:Nf(2)))
         allocate(self % c_y (NCOMP , 0:Nf(1), 0:Nf(2)))
         allocate(self % c_z (NCOMP , 0:Nf(1), 0:Nf(2)))
         allocate(self % mu  (NCOMP , 0:Nf(1), 0:Nf(2)))
         allocate(self % mu_x(NCOMP , 0:Nf(1), 0:Nf(2)))
         allocate(self % mu_y(NCOMP , 0:Nf(1), 0:Nf(2)))
         allocate(self % mu_z(NCOMP , 0:Nf(1), 0:Nf(2)))
         allocate(self % v   (1:NDIM, 0:Nf(1), 0:Nf(2)))
!
!        CH will never be the biggest memory requirement unless NSE are disabled
!        -----------------------------------------------------------------------
         interfaceFluxMemorySize = max(interfaceFluxMemorySize, NCOMP*nDIM*product(Nf+1))
#endif
!
!        Reserve memory for the interface fluxes
!        ---------------------------------------
         allocate(self % genericInterfaceFluxMemory(interfaceFluxMemorySize))

#if defined(NAVIERSTOKES) || defined(INCNS)
!
!        Point to NS by default
!        ----------------------
         call self % SetStorageToNS
#endif
!
!        -----------------
!        Initialize memory
!        -----------------
!
#if defined(NAVIERSTOKES) || defined(INCNS)
         self % QNS    = 0.0_RP
         
         self % U_xNS = 0.0_RP
         self % U_yNS = 0.0_RP
         self % U_zNS = 0.0_RP

         self % dFStar_dqF  = 0.0_RP
         self % dFStar_dqEl = 0.0_RP
#endif

#if defined(CAHNHILLIARD)
         self % c     = 0.0_RP
         self % c_x   = 0.0_RP
         self % c_y   = 0.0_RP
         self % c_z   = 0.0_RP
         self % mu    = 0.0_RP
         self % mu_x  = 0.0_RP
         self % mu_y  = 0.0_RP
         self % mu_z  = 0.0_RP
         self % v     = 0.0_RP
#endif

      end subroutine FaceStorage_Construct

      elemental subroutine FaceStorage_Destruct(self)
         implicit none
         class(FaceStorage_t), intent(inout) :: self
   
         self % currentlyLoaded = OFF

#if defined(NAVIERSTOKES) || defined(INCNS)
         safedeallocate(self % QNS)
         safedeallocate(self % U_xNS)
         safedeallocate(self % U_yNS)
         safedeallocate(self % U_zNS)
         safedeallocate(self % dFStar_dqF)
         safedeallocate(self % dFStar_dqEl)
         safedeallocate(self % dFv_dGradQF)
         safedeallocate(self % dFv_dGradQEl)
         safedeallocate(self % gradRho)
#endif
#if defined(CAHNHILLIARD)
         safedeallocate(self % c)
         safedeallocate(self % c_x)
         safedeallocate(self % c_y)
         safedeallocate(self % c_z)
         safedeallocate(self % mu)
         safedeallocate(self % mu_x)
         safedeallocate(self % mu_y)
         safedeallocate(self % mu_z)
         safedeallocate(self % v)
#endif
         safedeallocate(self % genericInterfaceFluxMemory)

         self % Q      => NULL()
         self % U_x    => NULL() ; self % U_y => NULL() ; self % U_z => NULL()
         self % unStar => NULL()
         self % fStar  => NULL()

      end subroutine FaceStorage_Destruct
#if defined(NAVIERSTOKES) || defined(INCNS)
      subroutine FaceStorage_SetStorageToNS(self)
         implicit none
         class(FaceStorage_t), target    :: self
         integer                         :: NNS, NGRADNS

         self % currentlyLoaded = NS

#if defined(NAVIERSTOKES)
         NNS = NCONS
         NGRADNS = NGRAD

#elif defined(INCNS)
         NNS = NINC
         NGRADNS = NINC        

#endif
!
!        Get sizes
!        ---------
         self % Q   (1:,0:,0:)            => self % QNS
         self % fStar(1:NNS, 0:self % Nel(1), 0:self % Nel(2)) => self % genericInterfaceFluxMemory

         self % genericInterfaceFluxMemory = 0.0_RP

         if ( allocated(self % U_xNS) ) then
            self % U_x (1:,0:,0:) => self % U_xNS
            self % U_y (1:,0:,0:) => self % U_yNS
            self % U_z (1:,0:,0:) => self % U_zNS
            self % unStar(1:NGRADNS, 1:NDIM, 0:self % Nel(1), 0:self % Nel(2)) => self % genericInterfaceFluxMemory
         end if

      end subroutine FaceStorage_SetStorageToNS
#endif
#if defined(CAHNHILLIARD)
      subroutine FaceStorage_SetStorageToCH_c(self)
         implicit none
         class(FaceStorage_t), target  :: self

         self % currentlyLoaded = C
!
!        Get sizes
!        ---------
         self % Q(1:,0:,0:)   => self % c
         self % U_x(1:,0:,0:) => self % c_x
         self % U_y(1:,0:,0:) => self % c_y
         self % U_z(1:,0:,0:) => self % c_z

         self % fStar(1:NCOMP,0:self % Nel(1),0:self % Nel(2))            => self % genericInterfaceFluxMemory
         self % unStar(1:NCOMP, 1:NDIM, 0:self % Nel(1), 0:self % Nel(2)) => self % genericInterfaceFluxMemory

         self % genericInterfaceFluxMemory = 0.0_RP

      end subroutine FaceStorage_SetStorageToCH_c

      subroutine FaceStorage_SetStorageToCH_mu(self)
         implicit none
         class(FaceStorage_t), target  :: self

         self % currentlyLoaded = MU

         self % Q(1:,0:,0:)   => self % mu
         self % U_x(1:,0:,0:) => self % mu_x
         self % U_y(1:,0:,0:) => self % mu_y
         self % U_z(1:,0:,0:) => self % mu_z

         self % fStar(1:NCOMP,0:self % Nel(1),0:self % Nel(2))            => self % genericInterfaceFluxMemory
         self % unStar(1:NCOMP, 1:NDIM, 0:self % Nel(1), 0:self % Nel(2)) => self % genericInterfaceFluxMemory

         self % genericInterfaceFluxMemory = 0.0_RP

      end subroutine FaceStorage_SetStorageToCH_mu
#endif
!
!/////////////////////////////////////////////////////////////////////////////////////
!
!           Statistics procedures
!           ---------------------
!
!/////////////////////////////////////////////////////////////////////////////////////
!
      subroutine Statistics_Construct(self, no_of_variables, N)
         implicit none
         class(Statistics_t)           :: self
         integer,          intent(in)  :: no_of_variables
         integer,          intent(in)  :: N(3)
!
!        Allocate and initialize
!        -----------------------
         allocate( self % data(no_of_variables, 0:N(1), 0:N(2), 0:N(3) ) ) 
         self % data = 0.0_RP

      end subroutine Statistics_Construct
   
      subroutine Statistics_Destruct(self)
         implicit none
         class(Statistics_t)     :: self

         safedeallocate( self % data )

      end subroutine Statistics_Destruct

      subroutine GetStorageEquations(off_, ns_, c_, mu_)
         implicit none  
         integer, intent(out) :: off_, ns_, c_, mu_

         off_ = OFF
         ns_  = NS
         c_   = C
         mu_  = MU

      end subroutine GetStorageEquations

end module StorageClass
