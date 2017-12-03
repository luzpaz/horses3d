!
!////////////////////////////////////////////////////////////////////////
!
!      ElementClass.f95
!      Created: 2008-06-04 15:34:44 -0400 
!      By: David Kopriva
!
!      Implements Algorithms:
!         Algorithm: 124: ElementClass (QuadElementClass)
!
!       The Quad Element class, Alg. 124. See Sec. 8.2.1.2. self has
!       been modified to add the association of a boundary name to an element
!       edge so that different boundary conditions can be applied to different
!       elements. The names of the boundaries (not necessarily the names of the
!       *boundary conditions* to be applied) are of length BC_STRING_LENGTH.
!       One will associate boundary conditions to boundaries in the routine
!       "ExternalState".
!
!       Modified 2D Code to move solution into element class. 5/14/15, 5:36 PM
!
!////////////////////////////////////////////////////////////////////////
!
      Module ElementClass
      USE SMConstants
      USE PolynomialInterpAndDerivsModule
      USE GaussQuadrature
      USE TransfiniteMapClass
      USE MappedGeometryClass
      USE MeshTypes
      USE ElementConnectivityDefinitions
      USE ConnectivityClass
      use StorageClass
      USE NodalStorageClass
      use PhysicsStorage
      IMPLICIT NONE

      private
      public   Element, axisMap, allocateElementStorage 
      public   DestructElement, PrintElement, SetElementBoundaryNames
      
      TYPE Element
         integer                                        :: eID               ! ID of this element
         integer                                        :: globID            ! globalID of the element
         integer                                        :: offsetIO          ! Offset from the first element for IO
         INTEGER                                        :: nodeIDs(8)
         integer                                        :: faceIDs(6)
         integer                                        :: faceSide(6)
         INTEGER, DIMENSION(3)                          :: Nxyz              ! Polynomial orders in every direction (Nx,Ny,Nz)
         TYPE(MappedGeometry)                           :: geom
         CHARACTER(LEN=BC_STRING_LENGTH)                :: boundaryName(6)
         CHARACTER(LEN=BC_STRING_LENGTH)                :: boundaryType(6)
         INTEGER                                        :: NumberOfConnections(6)
         TYPE(Connectivity)                             :: Connection(6)
         type(Storage_t)                                :: storage
         type(NodalStorage), pointer                    :: spAxi
         type(NodalStorage), pointer                    :: spAeta
         type(NodalStorage), pointer                    :: spAzeta
         type(TransfiniteHexMap)                        :: hexMap            ! High-order mapper
         contains
            procedure   :: Construct => HexElement_Construct
            procedure   :: ConstructGeometry => HexElement_ConstructGeometry
            procedure   :: FindPointWithCoords => HexElement_FindPointWithCoords
            procedure   :: EvaluateSolutionAtPoint => HexElement_EvaluateSolutionAtPoint
            procedure   :: ProlongSolutionToFaces => HexElement_ProlongSolutionToFaces
            procedure   :: ProlongGradientsToFaces => HexElement_ProlongGradientsToFaces
      END TYPE Element 
      
!
!     -------------------------------------------------------------------------
!!    axisMap gives the element local coordinate number for the two directions
!!    on each face. The coordinate numbers are given by (xi,eta,zeta) = (1,2,3).
!!    For instance, the two coordinate directions on Face 1 are (xi,zeta).
!     -------------------------------------------------------------------------
!
      INTEGER, DIMENSION(2,6) :: axisMap =                        &
                                 RESHAPE( (/1, 3,                 & ! Face 1 (x,z)
                                            1, 3,                 & ! Face 2 (x,z)
                                            1, 2,                 & ! Face 3 (x,y)
                                            2, 3,                 & ! Face 4 (y,z)
                                            1, 2,                 & ! Face 5 (x,y)
                                            2, 3/)                & ! Face 6 (y,z)
                                 ,(/2,6/))
            
      CONTAINS 
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE HexElement_Construct( self, spAxi, spAeta, spAzeta, nodeIDs, eID, globID)
         IMPLICIT NONE
         
         class(Element)             :: self
         TYPE(NodalStorage), target :: spAxi
         TYPE(NodalStorage), target :: spAeta
         TYPE(NodalStorage), target :: spAzeta
         INTEGER                 :: nodeIDs(8)
         integer                 :: eID, globID
         
         self % eID                 = eID
         self % globID              = globID
         self % nodeIDs             = nodeIDs
         self % Nxyz(1)             = spAxi   % N
         self % Nxyz(2)             = spAeta  % N
         self % Nxyz(3)             = spAzeta % N
         self % boundaryName        = emptyBCName
         self % boundaryType        = emptyBCName
         self % NumberOfConnections = 0
         self % spAxi   => spAxi
         self % spAeta  => spAeta
         self % spAzeta => spAzeta
!
!        ----------------------------------------
!        Solution Storage is allocated separately
!        ----------------------------------------
!
      END SUBROUTINE HexElement_Construct
!
!////////////////////////////////////////////////////////////////////////
!
!     ------------------------------------------------------------
!     Constructs the mapped geometry of the element (metric terms)
!     ------------------------------------------------------------
      subroutine HexElement_ConstructGeometry( self, hexMap)
         implicit none
         !--------------------------------------
         class(Element)         , intent(inout) :: self
         TYPE(TransfiniteHexMap), intent(in)    :: hexMap
         !--------------------------------------
         
         self % hexMap = hexMap
         CALL self % geom % Construct( self % spAxi, self % spAeta, self % spAzeta, hexMap )
         
      end subroutine HexElement_ConstructGeometry
!
!//////////////////////////////////////////////////////////////////////// 
! 
      SUBROUTINE allocateElementStorage(self, Nx, Ny, Nz, nEqn, nGradEqn, flowIsNavierStokes)  
         IMPLICIT NONE
         TYPE(Element)        :: self
         INTEGER, intent(in)  :: Nx, Ny, Nz, nEqn, nGradEqn
         LOGICAL, intent(in)  :: flowIsNavierStokes

         call self % Storage % Construct(Nx, Ny, Nz, nEqn, nGradEqn, flowIsNavierStokes)

      END SUBROUTINE allocateElementStorage
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE SetElementBoundaryNames( self, names ) 
         IMPLICIT NONE
         TYPE(Element)                   :: self
         CHARACTER(LEN=BC_STRING_LENGTH) :: names(6)
         INTEGER                         :: j
         
         DO j = 1, 6
            CALL toLower(names(j)) 
            self % boundaryName(j) = names(j)
         END DO  
      END SUBROUTINE SetElementBoundaryNames
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE DestructElement( self )
         IMPLICIT NONE
         TYPE(Element) :: self
         
         CALL self % geom % Destruct
         call self % Storage % Destruct   
         
         nullify( self % spAxi   )
         nullify( self % spAeta  )
         nullify( self % spAzeta )     

      END SUBROUTINE DestructElement
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE PrintElement( self, id )
         IMPLICIT NONE 
         TYPE(Element) :: self
         INTEGER      :: id
         PRINT *, id, self % nodeIDs
         PRINT *, "   ",self % boundaryName
      END SUBROUTINE PrintElement
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE SaveSolutionStorageToUnit( self, fUnit )
         IMPLICIT NONE
!
!        -----------------------
!        Save for a restart file
!        -----------------------
!
         TYPE(Element) :: self
         INTEGER       :: fUnit
         
         WRITE(funit) self % storage % Q
      
      END SUBROUTINE SaveSolutionStorageToUnit
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE LoadSolutionFromUnit( self, fUnit )
         IMPLICIT NONE
!
!        -----------------------
!        Save for a restart file
!        -----------------------
!
         TYPE(Element) :: self
         INTEGER       :: fUnit
         
         READ(funit) self % storage % Q
      
      END SUBROUTINE LoadSolutionFromUnit
!
!////////////////////////////////////////////////////////////////////////
!
      subroutine HexElement_ProlongSolutionToFaces(self, fFR, fBK, fBOT, fR, fT, fL)
         use FaceClass
         implicit none
         class(Element),   intent(in)  :: self
         class(Face),      intent(inout) :: fFR, fBK, fBOT, fR, fT, fL
!
!        ---------------
!        Local variables
!        ---------------
!
         integer  :: i, j, k, l, N(3)
         real(kind=RP), dimension(1:NCONS, 0:self % Nxyz(1), 0:self % Nxyz(3)) :: QFR, QBK
         real(kind=RP), dimension(1:NCONS, 0:self % Nxyz(1), 0:self % Nxyz(2)) :: QBOT, QT
         real(kind=RP), dimension(1:NCONS, 0:self % Nxyz(2), 0:self % Nxyz(3)) :: QL, QR

         N = self % Nxyz
!
!        *************************
!        Prolong solution to faces
!        *************************
!
         QL   = 0.0_RP     ; QR   = 0.0_RP
         QFR  = 0.0_RP     ; QBK  = 0.0_RP
         QBOT = 0.0_RP     ; QT   = 0.0_RP
         
         do k = 0, N(3) ; do j = 0, N(2) ; do i = 0, N(1)
            QL  (:,j,k)= QL  (:,j,k)+ self % storage % Q(:,i,j,k)* self % spAxi % v  (i,LEFT  )
            QR  (:,j,k)= QR  (:,j,k)+ self % storage % Q(:,i,j,k)* self % spAxi % v  (i,RIGHT )
            QFR (:,i,k)= QFR (:,i,k)+ self % storage % Q(:,i,j,k)* self % spAeta % v (j,FRONT )
            QBK (:,i,k)= QBK (:,i,k)+ self % storage % Q(:,i,j,k)* self % spAeta % v (j,BACK  )
            QBOT(:,i,j)= QBOT(:,i,j)+ self % storage % Q(:,i,j,k)* self % spAzeta % v(k,BOTTOM)
            QT  (:,i,j)= QT  (:,i,j)+ self % storage % Q(:,i,j,k)* self % spAzeta % v(k,TOP   )
         end do                   ; end do                   ; end do

         
         call fL   % AdaptSolutionToFace(N(2), N(3), QL   , self % faceSide(ELEFT  ))
         call fR   % AdaptSolutionToFace(N(2), N(3), QR   , self % faceSide(ERIGHT ))
         call fFR  % AdaptSolutionToFace(N(1), N(3), QFR  , self % faceSide(EFRONT ))
         call fBK  % AdaptSolutionToFace(N(1), N(3), QBK  , self % faceSide(EBACK  ))
         call fBOT % AdaptSolutionToFace(N(1), N(2), QBOT , self % faceSide(EBOTTOM))
         call fT   % AdaptSolutionToFace(N(1), N(2), QT   , self % faceSide(ETOP   ))

      end subroutine HexElement_ProlongSolutionToFaces

      subroutine HexElement_ProlongGradientsToFaces(self, fFR, fBK, fBOT, fR, fT, fL)
         use FaceClass
         implicit none
         class(Element),   intent(in)  :: self
         class(Face),      intent(inout) :: fFR, fBK, fBOT, fR, fT, fL
!
!        ---------------
!        Local variables
!        ---------------
!
         integer  :: i, j, k, l, N(3)
         real(kind=RP), dimension(N_GRAD_EQN, 0:self % Nxyz(1), 0:self % Nxyz(3)) :: UxFR, UyFR, UzFR
         real(kind=RP), dimension(N_GRAD_EQN, 0:self % Nxyz(1), 0:self % Nxyz(3)) :: UxBK, UyBK, UzBK
         real(kind=RP), dimension(N_GRAD_EQN, 0:self % Nxyz(1), 0:self % Nxyz(2)) :: UxBT, UyBT, UzBT
         real(kind=RP), dimension(N_GRAD_EQN, 0:self % Nxyz(1), 0:self % Nxyz(2)) :: UxT, UyT, UzT
         real(kind=RP), dimension(N_GRAD_EQN, 0:self % Nxyz(2), 0:self % Nxyz(3)) :: UxL, UyL, UzL
         real(kind=RP), dimension(N_GRAD_EQN, 0:self % Nxyz(2), 0:self % Nxyz(3)) :: UxR, UyR, UzR

         N = self % Nxyz
!
!        *************************
!        Prolong solution to faces
!        *************************
!
         UxL  = 0.0_RP ; UyL  = 0.0_RP ; UzL  = 0.0_RP
         UxR  = 0.0_RP ; UyR  = 0.0_RP ; UzR  = 0.0_RP
         UxFR = 0.0_RP ; UyFR = 0.0_RP ; UzFR = 0.0_RP
         UxBK = 0.0_RP ; UyBK = 0.0_RP ; UzBK = 0.0_RP
         UxBT = 0.0_RP ; UyBT = 0.0_RP ; UzBT = 0.0_RP
         UxT  = 0.0_RP ; UyT  = 0.0_RP ; UzT  = 0.0_RP
         
         do k = 0, N(3) ; do j = 0, N(2) ; do i = 0, N(1)
            UxL (:,j,k) = UxL (:,j,k) + self % storage % U_x(:,i,j,k)* self % spAxi   % v (i,LEFT  )
            UxR (:,j,k) = UxR (:,j,k) + self % storage % U_x(:,i,j,k)* self % spAxi   % v (i,RIGHT )
            UxFR(:,i,k) = UxFR(:,i,k) + self % storage % U_x(:,i,j,k)* self % spAeta  % v (j,FRONT )
            UxBK(:,i,k) = UxBK(:,i,k) + self % storage % U_x(:,i,j,k)* self % spAeta  % v (j,BACK  )
            UxBT(:,i,j) = UxBT(:,i,j) + self % storage % U_x(:,i,j,k)* self % spAzeta % v (k,BOTTOM)
            UxT (:,i,j) = UxT (:,i,j) + self % storage % U_x(:,i,j,k)* self % spAzeta % v (k,TOP   )

            UyL (:,j,k) = UyL (:,j,k) + self % storage % U_y(:,i,j,k)* self % spAxi   % v (i,LEFT  )
            UyR (:,j,k) = UyR (:,j,k) + self % storage % U_y(:,i,j,k)* self % spAxi   % v (i,RIGHT )
            UyFR(:,i,k) = UyFR(:,i,k) + self % storage % U_y(:,i,j,k)* self % spAeta  % v (j,FRONT )
            UyBK(:,i,k) = UyBK(:,i,k) + self % storage % U_y(:,i,j,k)* self % spAeta  % v (j,BACK  )
            UyBT(:,i,j) = UyBT(:,i,j) + self % storage % U_y(:,i,j,k)* self % spAzeta % v (k,BOTTOM)
            UyT (:,i,j) = UyT (:,i,j) + self % storage % U_y(:,i,j,k)* self % spAzeta % v (k,TOP   )

            UzL (:,j,k) = UzL (:,j,k) + self % storage % U_z(:,i,j,k)* self % spAxi   % v (i,LEFT  )
            UzR (:,j,k) = UzR (:,j,k) + self % storage % U_z(:,i,j,k)* self % spAxi   % v (i,RIGHT )
            UzFR(:,i,k) = UzFR(:,i,k) + self % storage % U_z(:,i,j,k)* self % spAeta  % v (j,FRONT )
            UzBK(:,i,k) = UzBK(:,i,k) + self % storage % U_z(:,i,j,k)* self % spAeta  % v (j,BACK  )
            UzBT(:,i,j) = UzBT(:,i,j) + self % storage % U_z(:,i,j,k)* self % spAzeta % v (k,BOTTOM)
            UzT (:,i,j) = UzT (:,i,j) + self % storage % U_z(:,i,j,k)* self % spAzeta % v (k,TOP   )

         end do                   ; end do                   ; end do
         
         call fL   % AdaptGradientsToFace(N(2), N(3), UxL , UyL , UzL , self % faceSide(ELEFT  ))
         call fR   % AdaptGradientsToFace(N(2), N(3), UxR , UyR , UzR , self % faceSide(ERIGHT ))
         call fFR  % AdaptGradientsToFace(N(1), N(3), UxFR, UyFR, UzFR, self % faceSide(EFRONT ))
         call fBK  % AdaptGradientsToFace(N(1), N(3), UxBK, UyBK, UzBK, self % faceSide(EBACK  ))
         call fBOT % AdaptGradientsToFace(N(1), N(2), UxBT, UyBT, UzBT, self % faceSide(EBOTTOM))
         call fT   % AdaptGradientsToFace(N(1), N(2), UxT , UyT , UzT , self % faceSide(ETOP   ))

      end subroutine HexElement_ProlongGradientsToFaces

!
!////////////////////////////////////////////////////////////////////////
!
      logical function HexElement_FindPointWithCoords(self, x, xi)
!
!        **********************************************************
!          
!           This function finds whether a point is inside or not 
!           of the element. This is done solving
!           the mapping non-linear system
!
!        **********************************************************
!          
!
         implicit none
         class(Element),      intent(in)  :: self
         real(kind=RP),       intent(in)  :: x(NDIM)
         real(kind=RP),       intent(out) :: xi(NDIM)
!
!        ----------------------------------
!        Newton iterative solver parameters
!        ----------------------------------
!
         integer,       parameter   :: N_MAX_ITER = 50
         real(kind=RP), parameter   :: TOL = 1.0e-12_RP
         integer,       parameter   :: STEP = 1.0_RP
!
!        ---------------
!        Local variables
!        ---------------
!
         integer                       :: i, j, k, iter
         real(kind=RP), parameter      :: INSIDE_TOL = 1.0e-08_RP
         real(kind=RP)                 :: lxi   (0:self % Nxyz(1)) 
         real(kind=RP)                 :: leta  (0:self % Nxyz(2)) 
         real(kind=RP)                 :: lzeta (0:self % Nxyz(3)) 
         real(kind=RP)                 :: dlxi   (0:self % Nxyz(1)) 
         real(kind=RP)                 :: dleta  (0:self % Nxyz(2)) 
         real(kind=RP)                 :: dlzeta (0:self % Nxyz(3)) 
         real(kind=RP)                 :: F(NDIM)
         real(kind=RP)                 :: Jac(NDIM,NDIM)
         real(kind=RP)                 :: dx(NDIM)
         interface
            function SolveThreeEquationLinearSystem(A,b)
               use SMConstants
               implicit none
               real(kind=RP), intent(in)  :: A(3,3)
               real(kind=RP), intent(in)  :: b(3)
               real(kind=RP)     :: SolveThreeEquationLinearSystem(3)
            end function SolveThreeEquationLinearSystem
         end interface
!
!        Initial seed
!        ------------      
         xi = 0.0_RP    

         do iter = 1 , N_MAX_ITER
!
!           Get Lagrange polynomials and derivatives
!           ----------------------------------------
            lxi     = self %spAxi % lj   (xi(1))
            leta    = self %spAeta % lj  (xi(2))
            lzeta   = self %spAzeta % lj (xi(3))
  
            F = 0.0_RP
            do k = 0, self %spAzeta % N   ; do j = 0, self %spAeta % N ; do i = 0, self %spAxi % N
               F = F + self % geom % x(:,i,j,k) * lxi(i) * leta(j) * lzeta(k)
            end do               ; end do             ; end do
   
            F = F - x
!
!           Stopping criteria: there are several
!           ------------------------------------
            if ( maxval(abs(F)) .lt. TOL ) exit
            if ( abs(xi(1)) .ge. 1.25_RP ) exit
            if ( abs(xi(2)) .ge. 1.25_RP ) exit
            if ( abs(xi(3)) .ge. 1.25_RP ) exit
!
!           Perform a step
!           --------------
            dlxi    = self %spAxi % dlj  (xi(1))
            dleta   = self %spAeta % dlj (xi(2))
            dlzeta  = self %spAzeta % dlj(xi(3))

            Jac = 0.0_RP
            do k = 0, self %spAzeta % N   ; do j = 0, self %spAeta % N ; do i = 0, self %spAxi % N
               Jac(:,1) = Jac(:,1) + self % geom % x(:,i,j,k) * dlxi(i) * leta(j) * lzeta(k) 
               Jac(:,2) = Jac(:,2) + self % geom % x(:,i,j,k) * lxi(i) * dleta(j) * lzeta(k) 
               Jac(:,3) = Jac(:,3) + self % geom % x(:,i,j,k) * lxi(i) * leta(j) * dlzeta(k) 
            end do               ; end do             ; end do

            dx = solveThreeEquationLinearSystem( Jac , -F )
            xi = xi + STEP * dx
   
         end do

         if ( (abs(xi(1)) .lt. 1.0_RP + INSIDE_TOL) .and. &
              (abs(xi(2)) .lt. 1.0_RP + INSIDE_TOL) .and. &
              (abs(xi(3)) .lt. 1.0_RP + INSIDE_TOL)          ) then
!
!           Solution is valid
!           -----------------
            HexElement_FindPointWithCoords = .true.
   
         else
!
!           Solution is not valid
!           ---------------------
            HexElement_FindPointWithCoords = .false.
         
         end if

      end function HexElement_FindPointWithCoords

      function HexElement_EvaluateSolutionAtPoint(self, xi)
         implicit none
         class(Element),   intent(in)    :: self
         real(kind=RP),    intent(in)    :: xi(NDIM)
         real(kind=RP)                   :: HexElement_EvaluateSolutionAtPoint(NCONS)
!
!        ---------------
!        Local variables
!        ---------------
!
         integer        :: i, j, k
         real(kind=RP)  :: lxi(0:self % Nxyz(1))
         real(kind=RP)  :: leta(0:self % Nxyz(2))
         real(kind=RP)  :: lzeta(0:self % Nxyz(3))
         real(kind=RP)  :: Q(NCONS)
!
!        Compute Lagrange basis
!        ----------------------
         lxi   = self %spAxi % lj(xi(1))
         leta  = self %spAeta % lj(xi(2))
         lzeta = self %spAzeta % lj(xi(3))
!
!        Compute the tensor product
!        --------------------------
         Q = 0.0_RP
      
         do k = 0, self % spAzeta % N   ; do j = 0, self % spAeta % N ; do i = 0, self % spAxi % N
            Q = Q + self % storage % Q(:,i,j,k) * lxi(i) * leta(j) * lzeta(k)
         end do               ; end do             ; end do   

         HexElement_EvaluateSolutionAtPoint = Q

      end function HexElement_EvaluateSolutionAtPoint
      
      END Module ElementClass
