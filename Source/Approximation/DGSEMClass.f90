
!////////////////////////////////////////////////////////////////////////
!
!      DGSEMClass.f95
!      Created: 2008-07-12 13:38:26 -0400 
!      By: David Kopriva
!
!      Basic class for the discontinuous Galerkin spectral element
!      solution of conservation laws.
!
!      Algorithms:
!         Algorithm 136: DGSEM Class
!         Algorithm 129: ConstructDGSem (Constructor)
!         Algorithm 138: ComputeTimeDerivative (TimeDerivative)
!         Algorithm 137: ComputeRiemannFluxes (EdgeFluxes)
!         Algorithm  35: InterpolateToFineMesh (2DCoarseToFineInterpolation)
!
!      Modified for 3D       6/11/15, 11:32 AM by DAK
!      Modified for mortars 25/04/17, 18:00    by arueda
!
!////////////////////////////////////////////////////////////////////////
!
      Module DGSEMClass
      
      USE NodalStorageClass
      USE HexMeshClass
      USE PhysicsStorage
      USE DGTimeDerivativeMethods
      
      IMPLICIT NONE
      
      ABSTRACT INTERFACE
         SUBROUTINE externalStateSubroutine(x,t,nHat,Q,boundaryName)
            USE SMConstants
            REAL(KIND=RP)   , INTENT(IN)    :: x(3), t, nHat(3)
            REAL(KIND=RP)   , INTENT(INOUT) :: Q(:)
            CHARACTER(LEN=*), INTENT(IN)    :: boundaryName
         END SUBROUTINE externalStateSubroutine
         
         SUBROUTINE externalGradientsSubroutine(x,t,nHat,gradU,boundaryName)
            USE SMConstants
            REAL(KIND=RP)   , INTENT(IN)    :: x(3), t, nHat(3)
            REAL(KIND=RP)   , INTENT(INOUT) :: gradU(:,:)
            CHARACTER(LEN=*), INTENT(IN)    :: boundaryName
         END SUBROUTINE externalGradientsSubroutine
      END INTERFACE
      
      TYPE DGSem
         REAL(KIND=RP)                                         :: maxResidual
         INTEGER                                               :: numberOfTimeSteps
         TYPE(NodalStorage)                                    :: spA
         TYPE(HexMesh)                                         :: mesh
         PROCEDURE(externalStateSubroutine)    , NOPASS, POINTER :: externalState => NULL()
         PROCEDURE(externalGradientsSubroutine), NOPASS, POINTER :: externalGradients => NULL()
!
!        ========         
         CONTAINS
!        ========         
!
         PROCEDURE :: construct => ConstructDGSem
         PROCEDURE :: destruct  => DestructDGSem   
         
         PROCEDURE :: GetQ
         PROCEDURE :: SetQ
         PROCEDURE :: GetQdot
         
         PROCEDURE :: SaveSolutionForRestart
         PROCEDURE :: LoadSolutionForRestart
            
      END TYPE DGSem
      
      TYPE Neighbour             ! arueda: added to introduce colored computation of numerical Jacobian (is this the best place to define this type??) - only usable for conforming meshes
         INTEGER :: elmnt(7)     ! arueda: "7" hardcoded for 3D hexahedrals... This definition must change if the code will be generalized
!~         INTEGER :: belmnt(6)    ! arueda: New name "belmnt" (boundary element) -old: "edge"... (same remark as above)  ! commented: Not used in the moment
      END TYPE Neighbour
      
      CONTAINS 
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE ConstructDGSem( self, polynomialOrder, meshFileName, &
                                 externalState, externalGradients, success )
      IMPLICIT NONE
!
!     --------------------------
!     Constructor for the class.
!     --------------------------
!
      CLASS(DGSem)     :: self
      INTEGER          :: polynomialOrder
      CHARACTER(LEN=*) :: meshFileName
      LOGICAL          :: success
      EXTERNAL         :: externalState, externalGradients
      
      INTEGER :: k
      INTERFACE
         SUBROUTINE externalState(x,t,nHat,Q,boundaryName)
            USE SMConstants
            REAL(KIND=RP)   , INTENT(IN)    :: x(3), t, nHat(3)
            REAL(KIND=RP)   , INTENT(INOUT) :: Q(:)
            CHARACTER(LEN=*), INTENT(IN)    :: boundaryName
         END SUBROUTINE externalState
         
         SUBROUTINE externalGradients(x,t,nHat,gradU,boundaryName)
            USE SMConstants
            REAL(KIND=RP)   , INTENT(IN)    :: x(3), t, nHat(3)
            REAL(KIND=RP)   , INTENT(INOUT) :: gradU(:,:)
            CHARACTER(LEN=*), INTENT(IN)    :: boundaryName
         END SUBROUTINE externalGradients
      END INTERFACE
      
      CALL self % spA % construct( polynomialOrder )
      CALL self % mesh % constructFromFile( meshfileName, self % spA, success )
      
      IF(.NOT. success) RETURN 
!
!     ------------------------
!     Allocate and zero memory
!     ------------------------
!
      DO k = 1, SIZE(self % mesh % elements) 
         CALL allocateElementStorage( self % mesh % elements(k), polynomialOrder, &
                                      N_EQN, N_GRAD_EQN, flowIsNavierStokes )
      END DO
!
!     ------------------------
!     Construct the mortar
!     ------------------------
!
      DO k=1, SIZE(self % mesh % faces)
         IF (self % mesh % faces(k) % FaceType == HMESH_INTERIOR) THEN !The mortar is only needed for the interior edges
            CALL ConstructMortarStorage( self % mesh % faces(k), N_EQN, N_GRAD_EQN, self % mesh % elements )
         END IF
      END DO
!
!     -----------------------
!     Set boundary conditions
!     -----------------------
!
      self % externalState     => externalState
      self % externalGradients => externalGradients
      
      call assignBoundaryConditions(self)
      
      END SUBROUTINE ConstructDGSem
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE DestructDGSem( self )
      IMPLICIT NONE 
      CLASS(DGSem) :: self
      
      CALL self % spA % destruct()
      CALL DestructMesh( self % mesh )
      self % externalState     => NULL()
      self % externalGradients => NULL()
      
      END SUBROUTINE DestructDGSem
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE SaveSolutionForRestart( self, fUnit ) 
         IMPLICIT NONE
         CLASS(DGSem)     :: self
         INTEGER          :: fUnit
         INTEGER          :: k

         DO k = 1, SIZE(self % mesh % elements) 
            WRITE(fUnit) self % mesh % elements(k) % Q
         END DO

      END SUBROUTINE SaveSolutionForRestart
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE LoadSolutionForRestart( self, fUnit ) 
         IMPLICIT NONE
         CLASS(DGSem)     :: self
         INTEGER          :: fUnit
         INTEGER          :: k

         DO k = 1, SIZE(self % mesh % elements) 
            READ(fUnit) self % mesh % elements(k) % Q
         END DO

      END SUBROUTINE LoadSolutionForRestart
!
!//////////////////////////////////////////////////////////////////////// 
! 
   SUBROUTINE SetQ(sem,Q)
      CLASS(DGSem)   ,     INTENT(INOUT)           :: sem 
      REAL(KIND = RP),     INTENT(IN)              :: Q(:)   
      
      INTEGER                                      :: Nx, Ny, Nz, l, i, j, k, counter, elm
      
      counter = 1
      DO elm = 1, size(sem%mesh%elements)
         Nx = sem%mesh%elements(elm)%N ! arueda: the routines were originally developed for a code that allows different polynomial orders in different directions. Notation conserved just for the sake of generality (future improvement -?)
         Ny = sem%mesh%elements(elm)%N
         Nz = sem%mesh%elements(elm)%N
         DO k = 0, Nz
            DO j = 0, Ny
               DO i = 0, Nx
                  DO l = 1,N_EQN
                     sem%mesh%elements(elm)%Q(i, j, k, l) = Q(counter) 
                     counter =  counter + 1
                  END DO
               END DO
            END DO
         END DO
      END DO 
         
   END SUBROUTINE SetQ
!
!////////////////////////////////////////////////////////////////////////////////////////       
!
   SUBROUTINE GetQ(sem,Q)
      CLASS(DGSem),        INTENT(INOUT)            :: sem
      REAL(KIND = RP),     INTENT(OUT)              :: Q(:)
      
      INTEGER                                       :: Nx, Ny, Nz, l, i, j, k, counter, elm
      
      counter = 1
      DO elm = 1, size(sem%mesh%elements)
         Nx = sem%mesh%elements(elm)%N ! arueda: the routines were originally developed for a code that allows different polynomial orders in different directions. Notation conserved just for the sake of generality (future improvement -?)
         Ny = sem%mesh%elements(elm)%N
         Nz = sem%mesh%elements(elm)%N
         DO k = 0, Nz
            DO j = 0, Ny
                DO i = 0, Nx
                  DO l = 1,N_EQN
                     Q(counter)  = sem%mesh%elements(elm)%Q(i, j, k, l)
                     counter =  counter + 1
                  END DO
                END DO
            END DO
         END DO
      END DO
      
   END SUBROUTINE GetQ
!
!////////////////////////////////////////////////////////////////////////////////////////      
!
   SUBROUTINE GetQdot(sem,Qdot)
      CLASS(DGSem),        INTENT(INOUT)            :: sem
      REAL(KIND = RP),     INTENT(OUT)              :: Qdot(:)
      
      INTEGER                                       :: Nx, Ny, Nz, l, i, j, k, counter, elm
      
      counter = 1
      DO elm = 1, size(sem%mesh%elements)
         Nx = sem%mesh%elements(elm)%N ! arueda: the routines were originally developed for a code that allows different polynomial orders in different directions. Notation conserved just for the sake of generality (future improvement -?)
         Ny = sem%mesh%elements(elm)%N
         Nz = sem%mesh%elements(elm)%N
         DO k = 0, Nz
            DO j = 0, Ny
               DO i = 0, Nx
                  DO l = 1,N_EQN
                     Qdot(counter)  = sem%mesh%elements(elm)%Qdot(i, j, k, l) 
                     counter =  counter + 1
                  END DO
               END DO
            END DO
         END DO
      END DO
      
   END SUBROUTINE GetQdot
!
!//////////////////////////////////////////////////////////////////////// 
! 
      SUBROUTINE assignBoundaryConditions(self)
!
!        ------------------------------------------------------------
!        Assign the boundary condition type to the boundaries through
!        their boundary names
!        ------------------------------------------------------------
!
         USE SharedBCModule
         IMPLICIT NONE  
!
!        ---------
!        Arguments
!        ---------
!
         CLASS(DGSem)     :: self
!
!        ---------------
!        Local variables
!        ---------------
!
         INTEGER                         :: eID, k
         CHARACTER(LEN=BC_STRING_LENGTH) :: boundaryType, boundaryName
         
         DO eID = 1, SIZE( self % mesh % elements)
            DO k = 1,6
               boundaryName = self % mesh % elements(eID) % boundaryName(k)
               IF ( boundaryName /= emptyBCName )     THEN
                  boundaryType = bcTypeDictionary % stringValueForKey(key             = boundaryName, &
                                                                      requestedLength = BC_STRING_LENGTH)
                  IF( LEN_TRIM(boundaryType) > 0) self % mesh % elements(eID) % boundaryType(k) = boundaryType
               END IF 
                                                                   
            END DO  
         END DO
         
      END SUBROUTINE assignBoundaryConditions
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE ComputeTimeDerivative( self, time )
         USE DGTimeDerivativeMethods
         IMPLICIT NONE 
!
!        ---------
!        Arguments
!        ---------
!
         TYPE(DGSem)   :: self
         REAL(KIND=RP) :: time
!
!        ---------------
!        Local variables
!        ---------------
!
         INTEGER :: k, N
!
         N = self % spA % N
!
!        -----------------------------------------
!        Prolongation of the solution to the faces
!        -----------------------------------------
!
!$omp parallel
!$omp do
         DO k = 1, SIZE(self % mesh % elements) 
            CALL ProlongToFaces( self % mesh % elements(k), self % spA )
         END DO
!$omp end do
!
!        -------------------------------------------------------
!        Inviscid Riemann fluxes from the solutions on the faces
!        -------------------------------------------------------
!
!openmp inside
         CALL ComputeRiemannFluxes( self, time )

         
         IF ( flowIsNavierStokes )     THEN
!
!           --------------------------------------
!           Set up the face Values on each element
!           --------------------------------------
!
!openmp inside
            CALL ComputeSolutionRiemannFluxes( self, time, self % externalState )
!
!           -----------------------------------
!           Compute the gradients over the mesh
!           -----------------------------------
!
!$omp do
            DO k = 1, SIZE(self%mesh%elements) 
               CALL ComputeDGGradient( self % mesh % elements(k), self % spA, time )
            END DO
!$omp end do 
!
!           ----------------------------------
!           Prolong the gradients to the faces
!           ----------------------------------
!
!$omp do
            DO k = 1, SIZE(self%mesh%elements) 
               CALL ProlongGradientToFaces( self % mesh % elements(k), self % spA )
            END DO
!$omp end do 
!
!           -------------------------
!           Compute gradient averages
!           -------------------------
!
!openmp inside
            CALL ComputeGradientAverages( self, time, self % externalGradients  )

         END IF

!
!        ------------------------
!        Compute time derivatives
!        ------------------------
!
!$omp do
         DO k = 1, SIZE(self % mesh % elements) 
            CALL LocalTimeDerivative( self % mesh % elements(k), self % spA, time )
         END DO
!$omp end do
!$omp end parallel

      END SUBROUTINE ComputeTimeDerivative
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE computeRiemannFluxes( self, time )
         USE Physics
         USE BoundaryConditionFunctions
         IMPLICIT NONE 
!
!        ---------
!        Arguments
!        ---------
!
         TYPE(DGSem)   :: self
         REAL(KIND=RP) :: time
!
!        ---------------
!        Local Variables
!        ---------------
!
         INTEGER       :: faceID
         INTEGER       :: eIDLeft, eIDRight
         INTEGER       :: fIDLeft
         
!$omp do         
         DO faceID = 1, SIZE( self % mesh % faces)
            eIDLeft  = self % mesh % faces(faceID) % elementIDs(1) 
            eIDRight = self % mesh % faces(faceID) % elementIDs(2)
            
            IF ( eIDRight == HMESH_NONE )     THEN
!
!              -------------
!              Boundary face
!              -------------
!
               fIDLeft  = self % mesh % faces(faceID) % elementSide(1)
               
               CALL computeBoundaryFlux(self % mesh % elements(eIDLeft), fIDLeft, time, self % externalState)
               
            ELSE 
!
!              -------------
!              Interior face
!              -------------
!
               
               CALL computeElementInterfaceFlux ( eL       = self % mesh % elements(eIDLeft)  , &
                                                  eR       = self % mesh % elements(eIDRight) , &
                                                  thisface = self % mesh % faces(faceID)      )
            END IF 

         END DO           
!$omp enddo          
         
      END SUBROUTINE computeRiemannFluxes
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE computeSolutionRiemannFluxes( self, time, externalStateProcedure )
         USE Physics
         USE BoundaryConditionFunctions
         IMPLICIT NONE 
!
!        ---------
!        Arguments
!        ---------
!
         TYPE(DGSem)   :: self
         REAL(KIND=RP) :: time
         
         EXTERNAL      :: externalStateProcedure
!
!        ---------------
!        Local Variables
!        ---------------
!
         INTEGER       :: faceID
         INTEGER       :: eIDLeft, eIDRight
         INTEGER       :: fIDLeft
         INTEGER       :: N
         
         REAL(KIND=RP) :: bvExt(N_EQN), UL(N_GRAD_EQN), UR(N_GRAD_EQN), d(N_GRAD_EQN)     
         
         INTEGER       :: i, j
        
         N = self % spA % N
!$omp do         
         DO faceID = 1, SIZE( self % mesh % faces)
            eIDLeft  = self % mesh % faces(faceID) % elementIDs(1) 
            eIDRight = self % mesh % faces(faceID) % elementIDs(2)
            
            IF ( eIDRight == HMESH_NONE )     THEN
               fIDLeft  = self % mesh % faces(faceID) % elementSide(1)
!
!              -------------
!              Boundary face
!              -------------
!
               DO j = 0, N
                  DO i = 0, N

                     bvExt = self % mesh % elements(eIDLeft) % Qb(:,i,j,fIDLeft)

                     CALL externalStateProcedure( self % mesh % elements(eIDLeft) % geom % xb(:,i,j,fIDLeft), &
                                                  time, &
                                                  self % mesh % elements(eIDLeft) % geom % normal(:,i,j,fIDLeft), &
                                                  bvExt,&
                                                  self % mesh % elements(eIDLeft) % boundaryType(fIDLeft) )                                                  
!
!              ---------------
!              u,v, T averages
!              ---------------
!
                     CALL GradientValuesForQ( self % mesh % elements(eIDLeft) % Qb(:,i,j,fIDLeft), UL )
                     CALL GradientValuesForQ( bvExt, UR )

                     d = 0.5_RP*(UL + UR)
               
                     self % mesh % elements(eIDLeft) % Ub (:,i,j,fIDLeft) = d
!
!              -----------------
!              Solution averages
!              -----------------
!
                     CALL DiffusionRiemannSolution( self % mesh % elements(eIDLeft) % geom % normal(:,i,j,fIDLeft), &
                                                    self % mesh % elements(eIDLeft) % Qb(:,i,j,fIDLeft), &
                                                    bvExt, &
                                                    self % mesh % elements(eIDLeft) % Qb(:,i,j,fIDLeft) )
                                                    
                     !self % mesh % elements(eIDLeft) % Qb(:,i,j,fIDLeft)    = &
                     !& 0.5_RP*( self % mesh % elements(eIDLeft) % Qb(:,i,j,fIDLeft) + bvExt )

                  END DO   
               END DO   
            
            ELSE 
!
!              -------------
!              Interior face
!              -------------
!
               CALL computeElementInterfaceAverage ( eL       = self % mesh % elements(eIDLeft)  , &
                                                     eR       = self % mesh % elements(eIDRight) , &
                                                     thisface = self % mesh % faces(faceID)      )
               
            END IF 

         END DO           
!$omp enddo         
         
      END SUBROUTINE computeSolutionRiemannFluxes      
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE ComputeGradientAverages( self, time, externalGradientsProcedure )
         USE Physics
         USE BoundaryConditionFunctions
         IMPLICIT NONE 
!
!        ---------
!        Arguments
!        ---------
!
         TYPE(DGSem)   :: self
         REAL(KIND=RP) :: time
         
         EXTERNAL      :: externalGradientsProcedure
!
!        ---------------
!        Local Variables
!        ---------------
!
         INTEGER       :: faceID
         INTEGER       :: eIDLeft, eIDRight
         INTEGER       :: fIDLeft
         INTEGER       :: N

         REAL(KIND=RP) :: UGradExt(3,N_GRAD_EQN)
         REAL(KIND=RP) :: UL(N_GRAD_EQN), UR(N_GRAD_EQN), d(N_GRAD_EQN)    
         
         INTEGER       :: i, j
        
         N = self % spA % N
!$omp do         
         DO faceID = 1, SIZE( self % mesh % faces)

            eIDLeft  = self % mesh % faces(faceID) % elementIDs(1) 
            eIDRight = self % mesh % faces(faceID) % elementIDs(2)
            fIDLeft  = self % mesh % faces(faceID) % elementSide(1)

            IF ( eIDRight == HMESH_NONE )     THEN
!
!              -------------
!              Boundary face
!              -------------
!
               DO j = 0, N
                  DO i = 0, N
                  
                     UGradExt(1,:) = self % mesh % elements(eIDLeft) % U_xb(:,i,j,fIDLeft)
                     UGradExt(2,:) = self % mesh % elements(eIDLeft) % U_yb(:,i,j,fIDLeft)
                     UGradExt(3,:) = self % mesh % elements(eIDLeft) % U_zb(:,i,j,fIDLeft)
                     
                     CALL externalGradientsProcedure( self % mesh % elements(eIDLeft) % geom % xb(:,i,j,fIDLeft), &
                                                  time, &
                                                  self % mesh % elements(eIDLeft) % geom % normal(:,i,j,fIDLeft), &
                                                  UGradExt,&
                                                  self % mesh % elements(eIDLeft) % boundaryType(fIDLeft) )
!
!                 --------
!                 x values
!                 --------
!
                     UL = self % mesh % elements(eIDLeft) % U_xb(:,i,j,fIDLeft)
                     UR = UGradExt(1,:)

                     d = 0.5_RP*(UL + UR)

                     self % mesh % elements(eIDLeft) % U_xb(:,i,j,fIDLeft) = d
!
!                 --------
!                 y values
!                 --------
!
                     UL = self % mesh % elements(eIDLeft) % U_yb(:,i,j,fIDLeft)
                     UR = UGradExt(2,:)

                     d = 0.5_RP*(UL + UR)

                     self % mesh % elements(eIDLeft) % U_yb(:,i,j,fIDLeft) = d
!
!                 --------
!                 z values
!                 --------
!
                     UL = self % mesh % elements(eIDLeft) % U_zb(:,i,j,fIDLeft)
                     UR = UGradExt(3,:)

                     d = 0.5_RP*(UL + UR)

                     self % mesh % elements(eIDLeft) % U_zb(:,i,j,fIDLeft) = d

                  END DO   
               END DO   
            
            ELSE 
!
!              -------------
!              Interior face
!              -------------
!
               CALL computeElementInterfaceGradientAverage  ( eL       = self % mesh % elements(eIDLeft)  , &
                                                              eR       = self % mesh % elements(eIDRight) , &
                                                              thisface = self % mesh % faces(faceID)      )
               
            END IF 

         END DO           
!$omp enddo         
         
      END SUBROUTINE computeGradientAverages
!
!//////////////////////////////////////////////////////////////////////// 
! 
      SUBROUTINE computeElementInterfaceFlux( eL, eR, thisface)
         USE Physics  
         IMPLICIT NONE  
!
!        ---------
!        Arguments
!        ---------
!
         TYPE(Element) :: eL, eR        !<> Left and right elements on interface
         TYPE(Face)    :: thisface      !<> Face inbetween
!
!        ---------------
!        Local variables
!        ---------------
!
         INTEGER       :: fIDLeft, fIDRight
         REAL(KIND=RP) :: norm(3)
         INTEGER       :: i,j,ii,jj
         INTEGER       :: Nx, Ny          ! Polynomial orders on the interface
         INTEGER       :: rotation
         
         fIDLeft  = thisface % elementSide(1)
         fIDRight = thisface % elementSide(2)
         Nx       = thisface % N                ! TODO: Change when anisotropic polynomials are implemented
         Ny       = thisface % N                ! TODO: Change when anisotropic polynomials are implemented
         rotation = thisface % rotation
!
!        -----------------
!        Project to mortar
!        -----------------
!
         CALL ProjectToMortar(thisface, eL % QB(:,:,:,fIDLeft), eR % QB(:,:,:,fIDright), N_EQN)
!
!        ----------------------
!        Compute interface flux
!        Using Riemann solver
!        ----------------------
!
         norm = eL % geom % normal(:,1,1,fIDLeft)
         DO j = 0, Ny
            DO i = 0, Nx
               CALL iijjIndexes(i,j,Nx,Ny,rotation,ii,jj)                              ! This turns according to the rotation of the elements
               CALL RiemannSolver(QLeft  = thisface % Phi % L(:,i,j)        , &
                                  QRight = thisface % Phi % R(:,ii,jj)      , &
                                  nHat   = norm                             , &        ! This works only for flat faces. TODO: Change nHat to be stored in face with the highest polynomial combination!!! 
                                  flux   = thisface % Phi % C(:,i,j) ) 
            END DO   
         END DO 
!
!        ------------------------
!        Project back to elements
!        ------------------------
!
         CALL ProjectFluxToElement  ( thisface                   , &
                                      eL % FStarb(:,:,:,fIDLeft) , &
                                      eR % FStarb(:,:,:,fIdright), &
                                      N_EQN )
!
!        ------------------------
!        Apply metrics correction
!        ------------------------
!
         ! Left element
         Nx = eL % N      ! TODO: Change when anisotropic polynomials are implemented
         Ny = eL % N      ! TODO: Change when anisotropic polynomials are implemented
         DO j = 0, Ny
            DO i = 0, Nx
               eL % FStarb(:,i,j,fIDLeft)  = eL % FStarb(:,i,j,fIDLeft)  * eL % geom % scal(i,j,fIDLeft)
            END DO   
         END DO
         
         ! Right element
         Nx = eR % N      ! TODO: Change when anisotropic polynomials are implemented
         Ny = eR % N      ! TODO: Change when anisotropic polynomials are implemented
         DO j = 0, Ny
            DO i = 0, Nx
               eR % FStarb(:,i,j,fIdright) = eR % FStarb(:,i,j,fIdright) * eR % geom % scal(i,j,fIdright)
            END DO   
         END DO
         
      END SUBROUTINE computeElementInterfaceFlux
!
!//////////////////////////////////////////////////////////////////////// 
! 
      SUBROUTINE computeElementInterfaceAverage( eL, eR, thisface)
         USE Physics  
         IMPLICIT NONE  
!
!        ---------
!        Arguments
!        ---------
!
         TYPE(Element) :: eL, eR        !<> Left and right elements on interface
         TYPE(Face)    :: thisface      !<> Face inbetween
!
!        ---------------
!        Local variables
!        ---------------
!
         REAL(KIND=RP) :: UL(N_GRAD_EQN), UR(N_GRAD_EQN)
         REAL(KIND=RP) :: d(N_GRAD_EQN)
         INTEGER       :: i,j,ii,jj
         INTEGER       :: fIDLeft, fIdright
         INTEGER       :: rotation
         INTEGER       :: Nx, Ny
         
         fIDLeft  = thisface % elementSide(1)
         fIDRight = thisface % elementSide(2)
         Nx       = thisface % N                ! TODO: Change when anisotropic polynomials are implemented
         Ny       = thisface % N                ! TODO: Change when anisotropic polynomials are implemented
         rotation = thisface % rotation
!
!        -----------------
!        Project to mortar
!        -----------------
!
         CALL ProjectToMortar(thisface, eL % QB(:,:,:,fIDLeft), eR % QB(:,:,:,fIDright), N_EQN)
!
!        ----------------------
!        Compute interface flux
!        Using BR1 (averages)
!        ----------------------
!
         DO j = 0, Ny
            DO i = 0, Nx
               CALL iijjIndexes(i,j,Nx,Ny,rotation,ii,jj)                              ! This turns according to the rotation of the elements
!
!                 ----------------
!                 u,v,w,T averages
!                 ----------------
!
               CALL GradientValuesForQ( Q  = thisface % Phi % L(:,i ,j ), U = UL )
               CALL GradientValuesForQ( Q  = thisface % Phi % R(:,ii,jj), U = UR )
               
               thisface % Phi % Caux(:,i,j) = 0.5_RP*(UL + UR)
!
!              -----------------
!              Solution averages
!              -----------------
!
               thisface % Phi % C(:,i,j) = 0.5_RP*( thisface % Phi % R(:,ii,jj) + thisface % Phi % L(:,i,j) )
            END DO   
         END DO 
!
!        ------------------------
!        Project back to elements
!        ------------------------
!
         CALL ProjectToElement(thisface,thisface % Phi % Caux, eL % Ub(:,:,:,fIDLeft), eR % Ub(:,:,:,fIDright), N_GRAD_EQN)
         CALL ProjectToElement(thisface,thisface % Phi % C   , eL % QB(:,:,:,fIDLeft), eR % QB(:,:,:,fIDright), N_EQN)
      
      END SUBROUTINE computeElementInterfaceAverage   
!
!//////////////////////////////////////////////////////////////////////// 
! 
      SUBROUTINE computeElementInterfaceGradientAverage( eL, eR, thisface)
         USE Physics  
         IMPLICIT NONE  
!
!        ---------
!        Arguments
!        ---------
!
         TYPE(Element) :: eL, eR        !<> Left and right elements on interface
         TYPE(Face)    :: thisface      !<> Face inbetween
!
!        ---------------
!        Local variables
!        ---------------
!
         INTEGER       :: i,j,ii,jj
         INTEGER       :: fIDLeft, fIdright
         INTEGER       :: rotation
         INTEGER       :: Nx, Ny
         
         fIDLeft  = thisface % elementSide(1)
         fIDRight = thisface % elementSide(2)
         Nx       = thisface % N                ! TODO: Change when anisotropic polynomials are implemented
         Ny       = thisface % N                ! TODO: Change when anisotropic polynomials are implemented
         rotation = thisface % rotation
         
!
!        ----------------------
!        Compute interface flux
!        Using BR1 (averages)
!        ----------------------
!
!
!              --------
!              x values
!              --------
!
         CALL ProjectToMortar(thisface, eL % U_xb(:,:,:,fIDLeft), eR % U_xb(:,:,:,fIDright), N_GRAD_EQN)
         
         DO j = 0, Ny
            DO i = 0, Nx
               CALL iijjIndexes(i,j,Nx,Ny,rotation,ii,jj)                    ! This turns according to the rotation of the elements
               
               thisface % Phi % Caux(:,i,j) = 0.5_RP* (thisface % Phi % L(:,i,j) + thisface % Phi % R(:,ii,jj) )
               
            END DO   
         END DO 
         
         CALL ProjectToElement(thisface,thisface % Phi % Caux, eL % U_xb(:,:,:,fIDLeft), eR % U_xb(:,:,:,fIDright), N_GRAD_EQN)
!
!              --------
!              y values
!              --------
!        
         CALL ProjectToMortar(thisface, eL % U_yb(:,:,:,fIDLeft), eR % U_yb(:,:,:,fIDright), N_GRAD_EQN) 
         
         DO j = 0, Ny
            DO i = 0, Nx
               CALL iijjIndexes(i,j,Nx,Ny,rotation,ii,jj)                    ! This turns according to the rotation of the elements

               thisface % Phi % Caux(:,i,j) = 0.5_RP* (thisface % Phi % L(:,i,j) + thisface % Phi % R(:,ii,jj) )

            END DO   
         END DO 
         
         CALL ProjectToElement(thisface,thisface % Phi % Caux, eL % U_yb(:,:,:,fIDLeft), eR % U_yb(:,:,:,fIDright), N_GRAD_EQN)
!
!              --------
!              z values
!              --------
!         
         CALL ProjectToMortar(thisface, eL % U_zb(:,:,:,fIDLeft), eR % U_zb(:,:,:,fIDright), N_GRAD_EQN) 
         
         DO j = 0, Ny
            DO i = 0, Nx
               CALL iijjIndexes(i,j,Nx,Ny,rotation,ii,jj)                    ! This turns according to the rotation of the elements
               
               thisface % Phi % Caux(:,i,j) = 0.5_RP* (thisface % Phi % L(:,i,j) + thisface % Phi % R(:,ii,jj) )
               
            END DO   
         END DO   
         
         CALL ProjectToElement(thisface,thisface % Phi % Caux, eL % U_zb(:,:,:,fIDLeft), eR % U_zb(:,:,:,fIDright), N_GRAD_EQN)
         
      END SUBROUTINE computeElementInterfaceGradientAverage            
!
!////////////////////////////////////////////////////////////////////////
!
      REAL(KIND=RP) FUNCTION MaxTimeStep( self, cfl ) 
         IMPLICIT NONE
         TYPE(DGSem)    :: self
         REAL(KIND=RP)  :: cfl
         
         
         MaxTimeStep  = cfl/MaximumEigenvalue( self )
      
      END FUNCTION MaxTimeStep
!
!////////////////////////////////////////////////////////////////////////
!
   FUNCTION MaximumEigenvalue( self )
!
!  -------------------------------------------------------------------
!  Estimate the maximum eigenvalue of the system. This
!  routine computes a heuristic based on the smallest mesh
!  spacing (which goes as 1/N^2) AND the eigenvalues of the
!  particular hyperbolic system being solved. This is not
!  the only way to estimate the eigenvalues, but it works in practice.
!  Other people use variations on this and we make no assertions that
!  it is the only or best way. Other variations look only at the smallest
!  mesh values, other account for differences across the element.
!  -------------------------------------------------------------------
!
      USE Physics
      
      IMPLICIT NONE
!
!     ---------
!     Arguments
!     ---------
!
      TYPE(DGSem), TARGET    :: self
!
!     ---------------
!     Local variables
!     ---------------
!
      REAL(KIND=RP)         :: eValues(3)
      REAL(KIND=RP)         :: dcsi, deta, dzet, jac, lamcsi, lamzet, lameta
      INTEGER               :: i, j, k, id
      INTEGER               :: N
      REAL(KIND=RP)         :: MaximumEigenvalue
      EXTERNAL              :: ComputeEigenvaluesForState
      REAL(KIND=RP)         :: Q(N_EQN)
!            
      MaximumEigenvalue = 0.0_RP
      
      N = self % spA % N
!
!     -----------------------------------------------------------
!     TODO:
!     dcsi, deta and dzet have been modified so they work for N=2
!     However, I'm not sure if this modification is OK.
!     Besides, problems are expected for N=0.
!     -----------------------------------------------------------
!
      IF ( N==0 ) THEN 
         PRINT*, "Error in MaximumEigenvalue function (N<1)"    
      ENDIF
        
      dcsi = 1.0_RP / abs( self % spA % xi(1) - self % spA % xi(0) )   
      deta = 1.0_RP / abs( self % spA % eta(1) - self % spA % eta(0) )
      dzet = 1.0_RP / abs( self % spA % zeta(1) - self % spA % zeta(0) )

      DO id = 1, SIZE(self % mesh % elements) 
         DO k = 0, N
            DO j = 0, N
               DO i = 0, N
!
!                 ------------------------------------------------------------
!                 The maximum eigenvalues for a particular state is determined
!                 by the physics.
!                 ------------------------------------------------------------
!
                  Q(1:N_EQN) = self % mesh % elements(id) % Q(i,j,k,1:N_EQN)
                  CALL ComputeEigenvaluesForState( Q , eValues )
!
!                 ----------------------------
!                 Compute contravariant values
!                 ----------------------------
!              
                  lamcsi =  ( self % mesh % elements(id) % geom % jGradXi(IX,i,j,k)   * eValues(IX) + &
        &                     self % mesh % elements(id) % geom % jGradXi(IY,i,j,k)   * eValues(IY) + &
        &                     self % mesh % elements(id) % geom % jGradXi(IZ,i,j,k)   * eValues(IZ) ) * dcsi
        
                  lameta =  ( self % mesh % elements(id) % geom % jGradEta(IX,i,j,k)  * eValues(IX) + &
        &                     self % mesh % elements(id) % geom % jGradEta(IY,i,j,k)  * eValues(IY) + &
        &                     self % mesh % elements(id) % geom % jGradEta(IZ,i,j,k)  * eValues(IZ) ) * deta
        
                  lamzet =  ( self % mesh % elements(id) % geom % jGradZeta(IX,i,j,k) * eValues(IX) + &
        &                     self % mesh % elements(id) % geom % jGradZeta(IY,i,j,k) * eValues(IY) + &
        &                     self % mesh % elements(id) % geom % jGradZeta(IZ,i,j,k) * eValues(IZ) ) * dzet
        
                  jac               = self % mesh % elements(id) % geom % jacobian(i,j,k)
                  MaximumEigenvalue = MAX( MaximumEigenvalue, ABS(lamcsi/jac) + ABS(lameta/jac) + ABS(lamzet/jac) )
               END DO
            END DO
         END DO
      END DO 
      
   END FUNCTION MaximumEigenvalue
      
   END Module DGSEMClass
