!
!////////////////////////////////////////////////////////////////////////
!
!      HexMesh.f95
!      Created: 2007-03-22 17:05:00 -0400 
!      By: David Kopriva  
!
!
!////////////////////////////////////////////////////////////////////////
!
#include "Includes.h"
MODULE HexMeshClass
      USE MeshTypes
      USE NodeClass
      USE ElementClass
      USE FaceClass
      USE TransfiniteMapClass
      use SharedBCModule
      use ElementConnectivityDefinitions
      use ZoneClass
      use PhysicsStorage
      IMPLICIT NONE
!
!     ---------------
!     Mesh definition
!     ---------------
!
      type HexMesh
         integer                                   :: numberOfFaces
         integer                                   :: nodeType
         integer                                   :: no_of_elements
         integer      , dimension(:), allocatable  :: Ns              !Polynomial orders of all elements
         type(Node)   , dimension(:), allocatable  :: nodes
         type(Face)   , dimension(:), allocatable  :: faces
         type(Element), dimension(:), allocatable  :: elements
         class(Zone_t), dimension(:), allocatable  :: zones
         contains
            procedure :: destruct          => DestructMesh
            procedure :: Describe          => DescribeMesh
            procedure :: ConstructZones    => HexMesh_ConstructZones
            procedure :: SetConnectivities => HexMesh_SetConnectivities
            procedure :: ConstructGeometry => HexMesh_ConstructGeometry
            procedure :: ProlongSolutionToFaces => HexMesh_ProlongSolutionToFaces
            procedure :: ProlongGradientsToFaces => HexMesh_ProlongGradientsToFaces
            procedure :: Export            => HexMesh_Export
            procedure :: SaveSolution      => HexMesh_SaveSolution
            procedure :: SaveStatistics    => HexMesh_SaveStatistics
            procedure :: ResetStatistics   => HexMesh_ResetStatistics
            procedure :: LoadSolution      => HexMesh_LoadSolution
            procedure :: FindPointWithCoords => HexMesh_FindPointWithCoords
            procedure :: WriteCoordFile
      end type HexMesh

      TYPE Neighbour         ! added to introduce colored computation of numerical Jacobian (is this the best place to define this type??) - only usable for conforming meshes
         INTEGER :: elmnt(7) ! "7" hardcoded for 3D hexahedrals in conforming meshes... This definition must change if the code is expected to be more general
      END TYPE Neighbour

!
!     -------------------------------------------------------------
!     Type containing the information of the surfaces of an element
!     -> This is used only for constructung the mesh by the readers
!     -------------------------------------------------------------
      type SurfInfo_t
         ! Variables to specify that the element is a hex8
         logical         :: IsHex8 = .FALSE.
         real(kind=RP)   :: corners(NDIM,NODES_PER_ELEMENT)
         ! Variables for general elements
         type(FacePatch) :: facePatches(6)
      end type SurfInfo_t
!
!     ========
      CONTAINS
!     ========
!
!     -----------
!     Destructors
!     -----------
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE DestructMesh( self )
         IMPLICIT NONE 
         CLASS(HexMesh) :: self
         INTEGER        :: j
!
!        -----
!        Nodes
!        -----
!
         DO j = 1, SIZE( self % nodes )
            CALL DestructNode( self % nodes(j)) 
         END DO  
         DEALLOCATE( self % nodes )
!
!        --------
!        Elements
!        --------
!
         DO j = 1, SIZE(self % elements) 
            CALL DestructElement( self % elements(j) )
         END DO
         DEALLOCATE( self % elements )
!
!        -----
!        Faces
!        -----
!
         DO j = 1, SIZE(self % faces) 
            call self % faces(j) % Destruct
         END DO
         DEALLOCATE( self % faces )
!
!        -----
!        Zones
!        -----
!
         if (allocated(self % zones)) DEALLOCATE( self % zones )

         
      END SUBROUTINE DestructMesh
!
!     -------------
!     Print methods
!     -------------
!
!////////////////////////////////////////////////////////////////////////
!
      SUBROUTINE PrintMesh( self ) 
      IMPLICIT NONE 
      TYPE(HexMesh) :: self
      INTEGER ::  k
      
      PRINT *, "Nodes..."
      DO k = 1, SIZE(self % nodes)
         CALL PrintNode( self % nodes(k), k )
      END DO
      PRINT *, "Elements..."
      DO k = 1, SIZE(self % elements) 
         CALL PrintElement( self % elements(k), k )
      END DO
      PRINT *, "Faces..."
      DO k = 1, SIZE(self % faces) 
         CALL  self % faces(k) % Print
      END DO
      
      END SUBROUTINE PrintMesh
!
!//////////////////////////////////////////////////////////////////////// 
! 
      SUBROUTINE ConstructFaces( self, success )
!
!     -------------------------------------------------------------
!     Go through the elements and find the unique faces in the mesh
!     -------------------------------------------------------------
!
         USE FTMultiIndexTableClass 
         USE FTValueClass
         
         IMPLICIT NONE  
         TYPE(HexMesh) :: self
         LOGICAL       :: success
         
         INTEGER                 :: eID, faceNumber
         INTEGER                 :: faceID
         INTEGER                 :: nodeIDs(8), faceNodeIDs(4), j
         
         CLASS(FTMultiIndexTable), POINTER  :: table
         CLASS(FTObject), POINTER :: obj
         CLASS(FTValue) , POINTER :: v
         
         ALLOCATE(table)
         CALL table % initWithSize( SIZE( self % nodes) )
         
         self % numberOfFaces = 0
         DO eID = 1, SIZE( self % elements )
         
            nodeIDs = self % elements(eID) % nodeIDs
            DO faceNumber = 1, 6
               DO j = 1, 4
                  faceNodeIDs(j) = nodeIDs(localFaceNode(j,faceNumber)) 
               END DO
            
               IF ( table % containsKeys(faceNodeIDs) )     THEN
!
!                 --------------------------------------------------------------
!                 Add this element to the slave side of the face associated with
!                 these nodes.
!                 --------------------------------------------------------------
!
                  obj => table % objectForKeys(faceNodeIDs)
                  v   => valueFromObject(obj)
                  faceID = v % integerValue()
                  
                  self % faces(faceID) % elementIDs(2)  = eID
                  self % faces(faceID) % elementSide(2) = faceNumber
                  self % faces(faceID) % FaceType       = HMESH_INTERIOR
                  self % faces(faceID) % rotation       = faceRotation(masterNodeIDs = self % faces(faceID) % nodeIDs       , &
                                                                       slaveNodeIDs  = faceNodeIDs                          , &
                                                                       masterSide    = self % faces(faceID) % elementSide(1), &
                                                                       slaveSide     = faceNumber)
               ELSE 
!
!                 ------------------
!                 Construct new face
!                 ------------------
!
                  self % numberOfFaces = self % numberOfFaces + 1
                  
                  IF(self % numberOfFaces > SIZE(self % faces))     THEN
          
                     CALL release(table)
                     PRINT *, "Too many faces for # of elements:", self % numberOfFaces, " vs ", SIZE(self % faces)
                     success = .FALSE.
                     RETURN  
                  END IF 
                  
                  CALL self % faces(self % numberOfFaces) % Construct(ID  = self % numberOfFaces, &
                                                                      nodeIDs = faceNodeIDs, &
                                                                      elementID = eID,       &
                                                                      side = faceNumber)

                  self % faces(self % numberOfFaces) % boundaryName = &
                           self % elements(eID) % boundaryName(faceNumber)
!
!                 ----------------------------------------------
!                 Mark which face is associated with these nodes
!                 ----------------------------------------------
!
                  ALLOCATE(v)
                  CALL v % initWithValue(self % numberOfFaces)
                  obj => v
                  CALL table % addObjectForKeys(obj,faceNodeIDs)
                  CALL release(v)
               END IF 
            END DO 
              
         END DO  
         
         CALL release(table)
         
      END SUBROUTINE ConstructFaces

      subroutine GetElementsFaceIDs(self)
         implicit none
         type(HexMesh), intent(inout)  :: self
!
!        ---------------
!        Local variables
!        ---------------
!
         integer  :: fID, eL, eR

         do fID = 1, size(self % faces)
            select case (self % faces(fID) % faceType)
            case (HMESH_INTERIOR)
               eL = self % faces(fID) % elementIDs(1)
               eR = self % faces(fID) % elementIDs(2)

               self % elements(eL) % faceIDs(self % faces(fID) % elementSide(1)) = fID
               self % elements(eR) % faceIDs(self % faces(fID) % elementSide(2)) = fID
               self % elements(eL) % faceSide(self % faces(fID) % elementSide(1)) = 1
               self % elements(eR) % faceSide(self % faces(fID) % elementSide(2)) = 2
            case default
               eL = self % faces(fID) % elementIDs(1)
               self % elements(eL) % faceIDs(self % faces(fID) % elementSide(1)) = fID
               self % elements(eL) % faceSide(self % faces(fID) % elementSide(1)) = 1

            end select
         end do

      end subroutine GetElementsFaceIDs
!
!//////////////////////////////////////////////////////////////////////// 
! 
!
!---------------------------------------------------------------------
!! Element faces can be rotated with respect to each other. Orientation
!! gives the relative orientation of the master (1) face to the 
!! slave (2) face . In this routine,
!! orientation is measured in 90 degree increments:
!!                   rotation angle = orientation*pi/2
!!
!! As an example, faceRotation = 1 <=> rotating master by 90 deg. 
!
      INTEGER pure FUNCTION faceRotation(masterNodeIDs, slaveNodeIDs, masterSide, slaveSide)
         IMPLICIT NONE 
         INTEGER, intent(in)               :: masterSide   , slaveSide    !< Sides connected in interface
         INTEGER, DIMENSION(4), intent(in) :: masterNodeIDs, slaveNodeIDs !< Node IDs
!
!        ---------------
!        Local variables
!        ---------------
!
         integer, dimension(4), parameter :: NEXTNODE = (/2,3,4,1/)
         INTEGER :: j
!
!        Rotate until both first nodes match (each j corresponds to a 90deg rotation)
!        -----------------------------------         
         DO j = 1, 4
            IF(masterNodeIDs(1) == slaveNodeIDs(j)) EXIT 
         END DO  
!
!        Check whether the orientation is same or opposite
!        -------------------------------------------------
         if ( masterNodeIDS(2) == slaveNodeIDs(NEXTNODE(j)) ) then
            faceRotation = j - 1 
         else
            faceRotation = j + 3
         end if
         
      END FUNCTION faceRotation
! 
!//////////////////////////////////////////////////////////////////////// 
!
      SUBROUTINE ConstructPeriodicFaces(self) 
      USE Physics
      IMPLICIT NONE  
! 
!------------------------------------------------------------------- 
! This subroutine looks for periodic boundary conditions. If they 
! are found, periodic+ face is set as an interior face. The slave 
! face is the periodic- face and will be deleted in the following
! step. 
!------------------------------------------------------------------- 
! 
! 
!-------------------- 
! External variables 
!-------------------- 
!  
      TYPE(HexMesh) :: self

! 
!-------------------- 
! Local variables 
!-------------------- 
! 
!
      REAL(KIND=RP) :: x1(NDIM), x2(NDIM)
      LOGICAL       :: master_matched(4), slave_matched(4)
      INTEGER       :: coord
      
      INTEGER       :: i,j,k,l 
      integer       :: zIDplus, zIDMinus, iFace, jFace
!
!     ---------------------------------------------
!     Loop to find faces with the label "periodic+"
!     ---------------------------------------------
!
!     ------------------------------
!     Loop zones with BC "periodic+"
!     ------------------------------
!
      if ( bcTypeDictionary % COUNT() .eq. 0 ) return
      do zIDPlus = 1, size(self % zones)
!
!        Cycle if the zone is not periodic+
!        ----------------------------------
         if ( trim(bcTypeDictionary % stringValueForKey(key = self % zones(zIDPlus) % Name, &
                                                      requestedLength = BC_STRING_LENGTH)) .ne. "periodic+") cycle
!
!        ------------------------------
!        Loop zones with BC "periodic-"
!        ------------------------------
!
         do zIDMinus = 1, size(self % zones)
!
!           Cycle if the zone is not periodic-
!           ----------------------------------
            if ( trim(bcTypeDictionary % stringValueForKey(key = self % zones(zIDMinus) % Name, &
                                                      requestedLength = BC_STRING_LENGTH)) .ne. "periodic-") cycle
!
!           Loop all faces in both zones
!           ----------------------------
            do iFace = 1, self % zones(zIDPlus) % no_of_faces;    do jFace = 1, self % zones(zIDMinus) % no_of_faces
               i = self % zones(zIDPlus) % faces(iFace)
               j = self % zones(zIDMinus) % faces(jFace)
!
!              ----------------------------------------------------------------------------------------
!              The index i is a periodic+ face
!              The index j is a periodic- face
!              We are looking for couples of periodic+ and periodic- faces where 2 of the 3 coordinates
!              in all the corners are shared. The non-shared coordinate has to be always the same one.
!              ----------------------------------------------------------------------------------------
!
               coord = 0                         ! This is the non-shared coordinate
               master_matched(:)   = .FALSE.     ! True if the master corner finds a partner
               slave_matched(:)    = .FALSE.     ! True if the slave corner finds a partner
               
               DO k = 1, 4
                  x1 = self%nodes(self%faces(i)%nodeIDs(k))%x                           !x1 is the master coordinate
                  DO l = 1, 4
                     IF (.NOT.slave_matched(l)) THEN 
                        x2 = self%nodes(self%faces(j)%nodeIDs(l))%x                     !x2 is the slave coordinate
                        CALL CompareTwoNodes(x1, x2, master_matched(k), coord)          !x1 and x2 are compared here
                        IF (master_matched(k)) THEN 
                           slave_matched(l) = .TRUE. 
                           EXIT
                        ENDIF  
                     ENDIF 
                  ENDDO 
                  IF (.NOT.master_matched(k)) EXIT  
               ENDDO          
               
               IF ( (master_matched(1)) .AND. (master_matched(2)) .AND. (master_matched(3)) .AND. (master_matched(4)) ) THEN
                  self % faces(i) % boundaryName   = ""
                  self % faces(i) % elementIDs(2)  = self % faces(j) % elementIDs(1)
                  self % faces(i) % elementSide(2) = self % faces(j) % elementSide(1)
                  self % faces(i) % FaceType       = HMESH_INTERIOR
                  self % faces(i) % rotation       = 0 !faceRotation(masterNodeIDs = self % faces(i) % nodeIDs       , &
                                                       !                slaveNodeIDs  = self % faces(j) % nodeIDs       , &
                                                       !                masterSide    = self % faces(i) % elementSide(1), &
                                                       !                slaveSide     = self % faces(j) % elementSide(2))

                                                                            
               ENDIF    
            end do;  end do
         end do
      end do
           
      END SUBROUTINE ConstructPeriodicFaces
! 
!//////////////////////////////////////////////////////////////////////// 
!     
      SUBROUTINE CompareTwoNodes(x1, x2, success, coord) 
      IMPLICIT NONE  
! 
!------------------------------------------------------------------- 
! Comparison of two nodes. If two of the three coordinates are the 
! same, there is success. If there is success, the coordinate which 
! is not the same is saved. If the initial value of coord is not 0, 
! only that coordinate is checked. 
!------------------------------------------------------------------- 
! 
! 
!     -------------------- 
!     External variables 
!     -------------------- 
!  
      REAL(KIND=RP) :: x1(3)
      REAL(KIND=RP) :: x2(3)
      LOGICAL       :: success
      INTEGER       :: coord 
!
!     ---------
!     Externals
!     ---------
!
      LOGICAL, EXTERNAL :: AlmostEqual
! 
!     -------------------- 
!     Local variables 
!     -------------------- 
! 
      INTEGER :: i
      INTEGER :: counter    
      
      counter = 0
      
      IF (coord == 0) THEN

         DO i = 1,3
            IF ( AlmostEqual( x1(i), x2(i) ) ) THEN 
               counter = counter + 1
            ELSE 
               coord = i
            ENDIF  
         ENDDO 
         
         IF (counter.ge.2) THEN 
            success = .TRUE.
         ELSE 
            success = .FALSE. 
         ENDIF  
         
      ELSE 

         DO i = 1,3
            IF (i /= coord) THEN 
               IF ( AlmostEqual( x1(i), x2(i) ) ) THEN 
                  counter = counter + 1
               ENDIF 
            ENDIF 
         ENDDO 
         
         IF (counter.ge.2) THEN 
            success = .TRUE.
         ELSE           
            success = .FALSE. 
         ENDIF  
   
      ENDIF
          
             
      END SUBROUTINE CompareTwoNodes
! 
!//////////////////////////////////////////////////////////////////////// 
!
      SUBROUTINE DeletePeriodicminusfaces(self) 
      IMPLICIT NONE  
! 
!------------------------------------------------------------------- 
! This subroutine looks for periodic boundary conditions. If they 
! are found, periodic+ face is set as an interior face. The slave 
! face is the periodic- face and will be deleted in the following
! step. 
!------------------------------------------------------------------- 
! 
! 
!     -------------------- 
!     External variables 
!     -------------------- 
!  
      TYPE(HexMesh) :: self
! 
!     -------------------- 
!     Local variables 
!     -------------------- 
! 
      TYPE(Face),ALLOCATABLE  :: dummy_faces(:)
      INTEGER                 :: i
      INTEGER                 :: iFace, numberOfFaces
      
         
      iFace = 0
      ALLOCATE( dummy_faces(self % numberOfFaces) )
      DO i = 1, self%numberOfFaces 
         IF (TRIM(bcTypeDictionary % stringValueForKey(key             = self%faces(i)%boundaryName, &
                                                      requestedLength = BC_STRING_LENGTH)) /= "periodic-") THEN 
            iFace = iFace + 1
            dummy_faces(iFace) = self%faces(i)
         ENDIF 
      ENDDO
       
      numberOfFaces = iFace

      IF (numberOfFaces /= self%numberOfFaces) THEN     
         PRINT*, "WARNING: FACE ROTATION IN PERIODIC BOUNDARY CONDITIONS NOT IMPLEMENTED YET"
         PRINT*, "IF A PROBLEM IS SUSPECTED, CONTACT THE DEVELOPERS WITH YOUR MESH FILE"
      ENDIF            

      DEALLOCATE(self%faces)
      ALLOCATE(self%faces(numberOfFaces))
      
      self%numberOfFaces = numberOfFaces
      
      DO i = 1, self%numberOfFaces
         self%faces(i) = dummy_faces(i)
      ENDDO 
      
!     Reassign zones
!     -----------------
      CALL ReassignZones(self % faces, self % zones)
      
      
      END SUBROUTINE DeletePeriodicminusfaces
! 
!//////////////////////////////////////////////////////////////////////// 
! 
      subroutine HexMesh_ProlongSolutionToFaces(self, spA)
         implicit none
         class(HexMesh),   intent(inout)  :: self
         class(NodalStorage), intent(in)  :: spA(0:)
!
!        ---------------
!        Local variables
!        ---------------
!
         integer  :: fIDs(6)
         integer  :: eID

!$omp do schedule(runtime)
         do eID = 1, size(self % elements)
            fIDs = self % elements(eID) % faceIDs
            call self % elements(eID) % ProlongSolutionToFaces(self % faces(fIDs(1)),&
                                                               self % faces(fIDs(2)),&
                                                               self % faces(fIDs(3)),&
                                                               self % faces(fIDs(4)),&
                                                               self % faces(fIDs(5)),&
                                                               self % faces(fIDs(6)) )
         end do
!$omp end do

      end subroutine HexMesh_ProlongSolutionToFaces
! 
!//////////////////////////////////////////////////////////////////////// 
! 
      subroutine HexMesh_ProlongGradientsToFaces(self, spA)
         implicit none
         class(HexMesh),   intent(inout)  :: self
         class(NodalStorage), intent(in)  :: spA(0:)
!
!        ---------------
!        Local variables
!        ---------------
!
         integer  :: fIDs(6)
         integer  :: eID

!$omp do schedule(runtime)
         do eID = 1, size(self % elements)
            fIDs = self % elements(eID) % faceIDs
            call self % elements(eID) % ProlongGradientsToFaces(self % faces(fIDs(1)),&
                                                                self % faces(fIDs(2)),&
                                                                self % faces(fIDs(3)),&
                                                                self % faces(fIDs(4)),&
                                                                self % faces(fIDs(5)),&
                                                                self % faces(fIDs(6)) )
         end do
!$omp end do

      end subroutine HexMesh_ProlongGradientsToFaces
! 
!//////////////////////////////////////////////////////////////////////// 
! 
      SUBROUTINE DescribeMesh( self , fileName )
      USE Headers
      IMPLICIT NONE
!
!--------------------------------------------------------------------
!  This subroutine describes the loaded mesh
!--------------------------------------------------------------------
!
!
!     ------------------
!     External variables
!     ------------------
!
      CLASS(HexMesh)    :: self
      CHARACTER(LEN=*)  :: fileName
!
!     ---------------
!     Local variables
!     ---------------
!
      INTEGER           :: fID, zoneID
      INTEGER           :: no_of_bdryfaces
      
      no_of_bdryfaces = 0
      
      write(STD_OUT,'(/)')
      call Section_Header("Reading mesh")
      write(STD_OUT,'(/)')
      
      call SubSection_Header('Mesh file "' // trim(fileName) // '".')

      write(STD_OUT,'(30X,A,A28,I10)') "->" , "Number of nodes: " , size ( self % nodes )
      write(STD_OUT,'(30X,A,A28,I10)') "->" , "Number of elements: " , size ( self % elements )
      write(STD_OUT,'(30X,A,A28,I10)') "->" , "Number of faces: " , size ( self % faces )
   
      do fID = 1 , size ( self % faces )
         if ( self % faces(fID) % faceType .ne. HMESH_INTERIOR) then
            no_of_bdryfaces = no_of_bdryfaces + 1
         end if
      end do

      write(STD_OUT,'(30X,A,A28,I10)') "->" , "Number of boundary faces: " , no_of_bdryfaces
      
!     Describe the zones
!     ------------------
      
      write(STD_OUT,'(/)')
      call Section_Header("Creating zones")
      write(STD_OUT,'(/)')
      
      do zoneID = 1, size(self % zones)
         WRITE(STD_OUT,'(30X,A,A7,I0,A15,A)') "->", "  Zone ",zoneID, " for boundary: ",trim(self % zones(zoneID) % Name)
         write(STD_OUT,'(32X,A28,I0)') 'Number of faces: ', self % zones(zoneID) % no_of_faces
      end do
      
      END SUBROUTINE DescribeMesh     
!
!////////////////////////////////////////////////////////////////////////
! 
      SUBROUTINE WriteCoordFile(self,FileName)
         USE PhysicsStorage
         IMPLICIT NONE
!
!        -----------------------------------------------------------------
!        This subroutine writes a *.coo file containing all the mesh nodes
!        that can be used for eigenvalue analysis using the TAUev code
!        -----------------------------------------------------------------
!
         !--------------------------------------------------------
         CLASS(HexMesh)       :: self        !<  this mesh
         CHARACTER(len=*)     :: FileName    !<  ...
         !--------------------------------------------------------
         INTEGER              :: NumOfElem
         INTEGER              :: i, j, k, el, Nx, Ny, Nz, ndof, cooh
         !--------------------------------------------------------
          
         NumOfElem = SIZE(self % elements)
!
!        ------------------------------------------------------------------------
!        Determine the number of degrees of freedom
!           TODO: Move this to another place if needed in other parts of the code
!        ------------------------------------------------------------------------
!
         ndof = 0
         DO el = 1, NumOfElem
            Nx = self % elements(el) % Nxyz(1)
            Ny = self % elements(el) % Nxyz(2)
            Nz = self % elements(el) % Nxyz(3)
            ndof = ndof + (Nx + 1)*(Ny + 1)*(Nz + 1)*N_EQN
         END DO
         
         OPEN(newunit=cooh, file=FileName, action='WRITE')
         
         WRITE(cooh,*) ndof, ndim   ! defined in PhysicsStorage
         DO el = 1, NumOfElem
            Nx = self % elements(el) % Nxyz(1)
            Ny = self % elements(el) % Nxyz(2)
            Nz = self % elements(el) % Nxyz(3)
            DO k = 0, Nz
               DO j = 0, Ny
                  DO i = 0, Nx
                     WRITE(cooh,*) self % elements(el) % geom % x(1,i,j,k), &
                                   self % elements(el) % geom % x(2,i,j,k), &
                                   self % elements(el) % geom % x(3,i,j,k)
                  END DO
               END DO
            END DO
         END DO
         
         CLOSE(cooh)
         
      END SUBROUTINE WriteCoordFile
!
!////////////////////////////////////////////////////////////////////////
!
!        Set element connectivities
!        --------------------------
!
!////////////////////////////////////////////////////////////////////////
!
      subroutine HexMesh_SetConnectivities(self,spA,nodes)
         implicit none
         class(HexMesh)       :: self
         type (NodalStorage)  :: spA(0:)
         integer              :: nodes
!
!        ---------------
!        Local variables
!        ---------------
!
         integer  :: fID, SideL, SideR
         integer  :: NelL(2), NelR(2), k ! Polynomial orders on left and right of a face

         do fID = 1, size(self % faces)
            associate(f => self % faces(fID))
            associate(eL => self % elements(f % elementIDs(1)))

!
!           Get polynomial orders of element on the left
!           --------------------------------------------

            NelL = eL % Nxyz(axisMap(:, f % elementSide(1)))

            if ( f % faceType .eq. HMESH_INTERIOR ) then
               associate(eR => self % elements(f % elementIDs(2)))
!
!              Get polynomial orders of element on the right
!              ---------------------------------------------

               NelR = eR % Nxyz(axisMap(:, f % elementSide(2)))

!
!              Fill connectivity of element type
!              ---------------------------------
               
               SideL = f % elementSide(1)
               SideR = f % elementSide(2)
               
               eL % Connection( SideL ) % ElementIDs(1) = eR % eID
               eR % Connection( SideR ) % ElementIDs(1) = eL % eID
               
               end associate
            else
               NelR = NelL
            end if
            
            call f % LinkWithElements(N_EQN, N_GRAD_EQN, NelL, NelR, nodes, spA)
            
            end associate
            end associate
            
         end do
         
      end subroutine HexMesh_SetConnectivities
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!     -----------------------------------------------------------------------------
!     Construct geometry of faces and elements
!     -> This routine guarantees that the mapping is subparametric or isoparametric
!     -----------------------------------------------------------------------------
      subroutine HexMesh_ConstructGeometry(self,spA,SurfInfo)
         implicit none
         !--------------------------------
         class(HexMesh)    , intent(inout) :: self
         type(NodalStorage), intent(in)    :: spA(0:)
         type(SurfInfo_t)  , intent(inout) :: SurfInfo(:)
         !--------------------------------
         integer :: fID, eID           ! Face and element counters
         integer :: eIDLeft, eIDRight  ! Element IDs on left and right of a face
         integer :: SideIDL, SideIDR   ! Side of elements on left and right of a face
         integer :: buffer             ! A temporal variable
         integer :: i
         integer :: NSurfL(2), NSurfR(2) ! Polynomial order the face was constructef with  
         
         integer                    :: CLN(2)            ! Chebyshev-Lobatto face orders
         REAL(KIND=RP)              :: corners(NDIM,NODES_PER_ELEMENT) ! Variable just for initializing purposes
         real(kind=RP), allocatable :: xiCL(:), etaCL(:) ! Chebyshev-Lobatto node positions on face
         real(kind=RP), allocatable :: faceCL(:,:,:)     ! Coordinates of the Chebyshev-Lobatto nodes on the face
         
         type(TransfiniteHexMap), pointer :: hexMap, hex8Map, genHexMap
         !--------------------------------
         
         corners = 0._RP
         
!
!        --------------------------------------------------------------
!        Check surfaces' integrity and adapt them to the solution order
!        --------------------------------------------------------------
!
         
         do fID=1, size(self % faces)
            associate( f => self % faces(fID) )
            
!
!           Check if the surfaces description in mesh file is consistent 
!           ------------------------------------------------------------
            
            eIDLeft  = f % elementIDs(1)
            SideIDL  = f % elementSide(1)
            NSurfL   = SurfInfo(eIDLeft)  % facePatches(SideIDL) % noOfKnots - 1
            
            if ( f % faceType == HMESH_INTERIOR ) then
               eIDRight = f % elementIDs(2)
               SideIDR  = f % elementSide(2)
               NSurfR   = SurfInfo(eIDRight) % facePatches(SideIDR) % noOfKnots - 1
            
!              If both surfaces are of order 1.. There's no need to continue analyzing face
!              ----------------------------------------------------------------------------
            
               if     ((SurfInfo(eIDLeft)  % IsHex8) .and. (SurfInfo(eIDRight) % IsHex8)) then
                  cycle
               elseif ((SurfInfo(eIDLeft)  % IsHex8) .and. all(NSurfR == 1) ) then
                  cycle
               elseif ((SurfInfo(eIDRight) % IsHex8) .and. all(NSurfL == 1) ) then
                  cycle
               elseif (all(NSurfL == 1) .and. all(NSurfR == 1) ) then
                  cycle
               elseif (any(NSurfL /= NSurfR)) then ! Only works for mesh files with isotropic boundary orders
                  write(STD_OUT,*) 'WARNING: Curved face definitions in mesh are not consistent.'
                  write(STD_OUT,*) '   Face:    ', fID
                  write(STD_OUT,*) '   Elements:', f % elementIDs
                  write(STD_OUT,*) '   N Left:  ', SurfInfo(eIDLeft) % facePatches(SideIDL) % noOfKnots - 1
                  write(STD_OUT,*) '   N Right: ', SurfInfo(eIDRight) % facePatches(SideIDR) % noOfKnots - 1
               end if
            
               CLN(1) = min(f % NfLeft(1),f % NfRight(1))
               CLN(2) = min(f % NfLeft(2),f % NfRight(2))
            else
               if     (SurfInfo(eIDLeft)  % IsHex8 .or. all(NSurfL == 1)) cycle
               
               CLN(1) = f % NfLeft(1)
               CLN(2) = f % NfLeft(2)
            end if
            
!           Adapt the curved face order to the polynomial order
!           ---------------------------------------------------
            
            if (any(CLN < NSurfL)) then
               
               ! Element on the left 
               ! -------------------
               
               allocate(xiCL(CLN(1)+1), etaCL(CLN(2)+1))
               allocate(faceCL(1:3,CLN(1)+1,CLN(2)+1))
               xiCL  = (/ ( -cos((i-1.0_RP)*PI/CLN(1)),i=1, CLN(1)+1) /)
               etaCL = (/ ( -cos((i-1.0_RP)*PI/CLN(2)),i=1, CLN(2)+1) /)
               
               call ProjectFaceToNewPoints(SurfInfo(eIDLeft) % facePatches(SideIDL), CLN(1), xiCL , CLN(2), etaCL, faceCL)
               call SurfInfo(eIDLeft) % facePatches(SideIDL) % Destruct()
               call SurfInfo(eIDLeft) % facePatches(SideIDL) % Construct(xiCL,etaCL,faceCL) 
               
               if ( f % faceType == HMESH_INTERIOR ) then
                  
                  ! Element on the right
                  ! --------------------
                                    
                  SELECT CASE ( f % rotation )
                  case ( 1, 3, 4, 6 ) ! Local x and y axis are perpendicular
                     if (CLN(1) /= CLN(2)) then
                        buffer = CLN(1)
                        CLN(1) = CLN(2)
                        CLN(2) = buffer
                        
                        deallocate(xiCL, etaCL, faceCL)
                        allocate(xiCL(CLN(1)+1), etaCL(CLN(2)+1))
                        allocate(faceCL(1:3,CLN(1)+1,CLN(2)+1))
                        xiCL  = (/ ( -cos((i-1.0_RP)*PI/CLN(1)),i=1, CLN(1)+1) /)
                        etaCL = (/ ( -cos((i-1.0_RP)*PI/CLN(2)),i=1, CLN(2)+1) /)
                     end if
                  end SELECT
                  
                  call ProjectFaceToNewPoints(SurfInfo(eIDRight) % facePatches(SideIDR), CLN(1), xiCL , CLN(2), etaCL, faceCL)
                  call SurfInfo(eIDRight) % facePatches(SideIDR) % Destruct()
                  call SurfInfo(eIDRight) % facePatches(SideIDR) % Construct(xiCL,etaCL,faceCL) 
               end if   
               
               deallocate(xiCL, etaCL, faceCL)
               
            end if
            
            end associate
         end do
         
!
!        ----------------------------
!        Construct elements' geometry
!        ----------------------------
!
         
         allocate(hex8Map)
         call hex8Map % constructWithCorners(corners)
         allocate(genHexMap)
         
         do eID=1, size(self % elements)
            
            if (SurfInfo(eID) % IsHex8) then
               call hex8Map % setCorners(SurfInfo(eID) % corners)
               hexMap => hex8Map
            else
               CALL genHexMap % destruct()
               CALL genHexMap % constructWithFaces(SurfInfo(eID) % facePatches)
               
               hexMap => genHexMap
            end if
            
            call self % elements(eID) % ConstructGeometry (hexMap)
            
         end do
         
!
!        -------------------------
!        Construct faces' geometry
!        -------------------------
!
         
         do fID=1, size(self % faces)
            associate(f => self % faces(fID))
            associate(eL => self % elements(f % elementIDs(1)))
            call f % geom % construct(f % Nf, f % NelLeft, eL % Nxyz, & 
                                      spA(f % Nf), spA(eL % Nxyz), &
                                      eL % geom, eL % hexMap, f % elementSide(1))
            
            end associate
            end associate
         end do
         
!
!        ---------
!        Finish up
!        ---------
!
         CALL hex8Map % destruct()
         DEALLOCATE(hex8Map)
         CALL genHexMap % destruct()
         DEALLOCATE(genHexMap)
         
      end subroutine HexMesh_ConstructGeometry
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!     ---------------------------
!     Export mesh to a hmesh file
!     ---------------------------
      subroutine HexMesh_Export(self, fileName)
         use SolutionFile
         implicit none
         class(HexMesh),   intent(in)     :: self
         character(len=*), intent(in)     :: fileName
!
!        ---------------
!        Local variables
!        ---------------
!
         integer        :: fID, eID
         character(len=LINE_LENGTH)    :: meshName
         real(kind=RP), parameter      :: refs(NO_OF_SAVED_REFS) = 0.0_RP
         interface
            character(len=LINE_LENGTH) function RemovePath( inputLine )
               use SMConstants
               implicit none
               character(len=*)     :: inputLine
            end function RemovePath
      
            character(len=LINE_LENGTH) function getFileName( inputLine )
               use SMConstants
               implicit none
               character(len=*)     :: inputLine
            end function getFileName
         end interface

            
!
!        Create file: it will be contained in ./MESH
!        -------------------------------------------
         meshName = "./MESH/" // trim(removePath(getFileName(fileName))) // ".hmesh"
         fID = CreateNewSolutionFile( trim(meshName), MESH_FILE, self % nodeType, self % no_of_elements, 0, 0.0_RP, refs)
!
!        Introduce all element nodal coordinates
!        ---------------------------------------
         do eID = 1, self % no_of_elements
            call writeArray(fID, self % elements(eID) % geom % x)
         end do
!
!        Close the file
!        --------------
         call CloseSolutionFile(fID)
         
      end subroutine HexMesh_Export

      subroutine HexMesh_SaveSolution(self, iter, time, name, saveGradients)
         use SolutionFile
         implicit none
         class(HexMesh),      intent(in)        :: self
         integer,             intent(in)        :: iter
         real(kind=RP),       intent(in)        :: time
         character(len=*),    intent(in)        :: name
         logical,             intent(in)        :: saveGradients
!
!        ---------------
!        Local variables
!        ---------------
!
         integer  :: fid, eID
         real(kind=RP)                    :: refs(NO_OF_SAVED_REFS) 
!
!        Gather reference quantities
!        ---------------------------
         refs(GAMMA_REF) = thermodynamics % gamma
         refs(RGAS_REF)  = thermodynamics % R
         refs(RHO_REF)   = refValues      % rho
         refs(V_REF)     = refValues      % V
         refs(T_REF)     = refValues      % T
         refs(MACH_REF)  = dimensionless  % Mach
!
!        Create new file
!        ---------------
         if ( saveGradients ) then
            fid = CreateNewSolutionFile(trim(name),SOLUTION_AND_GRADIENTS_FILE, self % nodeType, self % no_of_elements, iter, time, refs)
         else
            fid = CreateNewSolutionFile(trim(name),SOLUTION_FILE, self % nodeType, self % no_of_elements, iter, time, refs)
         end if
!
!        Write arrays
!        ------------
         do eID = 1, self % no_of_elements
            associate( e => self % elements(eID) )
            call writeArray(fid, e % storage % Q)
            if ( saveGradients ) then
               write(fid) e % storage % U_x
               write(fid) e % storage % U_y
               write(fid) e % storage % U_z
            end if
            end associate
         end do

         call CloseSolutionFile(fid)

      end subroutine HexMesh_SaveSolution

      subroutine HexMesh_SaveStatistics(self, iter, time, name)
         use SolutionFile
         implicit none
         class(HexMesh),      intent(in)        :: self
         integer,             intent(in)        :: iter
         real(kind=RP),       intent(in)        :: time
         character(len=*),    intent(in)        :: name
!
!        ---------------
!        Local variables
!        ---------------
!
         integer  :: fid, eID
         real(kind=RP)                    :: refs(NO_OF_SAVED_REFS) 
!
!        Gather reference quantities
!        ---------------------------
         refs(GAMMA_REF) = thermodynamics % gamma
         refs(RGAS_REF)  = thermodynamics % R
         refs(RHO_REF)   = refValues      % rho
         refs(V_REF)     = refValues      % V
         refs(T_REF)     = refValues      % T
         refs(MACH_REF)  = dimensionless  % Mach
!
!        Create new file
!        ---------------
         fid = CreateNewSolutionFile(trim(name),STATS_FILE, self % nodeType, self % no_of_elements, iter, time, refs)
!
!        Write arrays
!        ------------
         do eID = 1, self % no_of_elements
            associate( e => self % elements(eID) )
            call writeArray(fid, e % storage % stats % data)
            end associate
         end do

      end subroutine HexMesh_SaveStatistics

      subroutine HexMesh_ResetStatistics(self)
         implicit none
         class(HexMesh)       :: self
!
!        ---------------
!        Local variables
!        ---------------
!
         integer     :: eID

         do eID = 1, self % no_of_elements
            self % elements(eID) % storage % stats % data = 0.0_RP
         end do

      end subroutine HexMesh_ResetStatistics

      subroutine HexMesh_LoadSolution( self, fileName, initial_iteration, initial_time ) 
         use SolutionFile
         IMPLICIT NONE
         CLASS(HexMesh)             :: self
         character(len=*)           :: fileName
         integer,       intent(out) :: initial_iteration
         real(kind=RP), intent(out) :: initial_time
         
!
!        ---------------
!        Local variables
!        ---------------
!
         INTEGER          :: fID, eID, fileType, no_of_elements, flag, nodetype
         integer          :: Nxp1, Nyp1, Nzp1, no_of_eqs
         character(len=SOLFILE_STR_LEN)      :: rstName
!
!        Open the file
!        -------------
         open(newunit = fID, file=trim(fileName), status="old", action="read", form="unformatted")
!
!        Get the file title
!        ------------------
         read(fID) rstName
!
!        Get the file type
!        -----------------
         read(fID) fileType

         select case (fileType)
         case(MESH_FILE)
            print*, "The selected restart file is a mesh file"
            errorMessage(STD_OUT)
            stop

         case(SOLUTION_FILE)
         case(SOLUTION_AND_GRADIENTS_FILE)
         case(STATS_FILE)
            print*, "The selected restart file is a statistics file"
            errorMessage(STD_OUT)
            stop
         case default
            print*, "Unknown restart file format"
            errorMessage(STD_OUT)
            stop
         end select
!
!        Get the node type
!        -----------------
         read(fID) nodeType

         if ( nodeType .ne. self % nodeType ) then
            print*, "Solution file uses a different discretization nodes that the mesh."
            errorMessage(STD_OUT)
         end if
!
!        Read the number of elements
!        ---------------------------
         read(fID) no_of_elements

         if ( no_of_elements .ne. size(self % elements) ) then
            write(STD_OUT,'(A,A)') "The number of elements stored in the restart file ", &
                                   "do not match that of the mesh file"
            errorMessage(STD_OUT)
            stop
         end if
!
!        Read the initial iteration and time
!        -----------------------------------
         read(fID) initial_iteration
         read(fID) initial_time          
!
!        Read the reference values
!        -------------------------
         read(fID) 
!
!        Read the terminator indicator
!        -----------------------------
         read(fID) flag

         if ( flag .ne. BEGINNING_DATA ) then
            print*, "Beginning data flag was not found in the file."
            errorMessage(STD_OUT)
            stop
         end if
!
!        Read elements data
!        ------------------
         do eID = 1, size(self % elements)
            associate( e => self % elements(eID) )
            read(fID)
            read(fID) no_of_eqs, Nxp1, Nyp1, Nzp1
            if (      ((Nxp1-1) .ne. e % Nxyz(1)) &
                 .or. ((Nyp1-1) .ne. e % Nxyz(2)) &
                 .or. ((Nzp1-1) .ne. e % Nxyz(3)) &
                 .or. (no_of_eqs .ne. NCONS )       ) then
               write(STD_OUT,'(A,I0,A)') "Error reading restart file: wrong dimension for element "&
                                           ,eID,"."

               write(STD_OUT,'(A,I0,A,I0,A,I0,A)') "Element dimensions: ", e % Nxyz(1), &
                                                                     " ,", e % Nxyz(2), &
                                                                     " ,", e % Nxyz(3), &
                                                                     "."
                                                                     
               write(STD_OUT,'(A,I0,A,I0,A,I0,A)') "Restart dimensions: ", Nxp1-1, &
                                                                     " ,", Nyp1-1, &
                                                                     " ,", Nzp1-1, &
                                                                     "."

               errorMessage(STD_OUT)
               stop
            end if

            read(fID) e % storage % Q 
!
!           Skip the gradients record if proceeds
!           -------------------------------------   
            if ( fileType .eq. SOLUTION_AND_GRADIENTS_FILE ) then
               read(fID)
               read(fID)
               read(fID)
            end if
            end associate
         end do
!
!        Close the file
!        --------------
         close(fID)

      END SUBROUTINE HexMesh_LoadSolution
!
!////////////////////////////////////////////////////////////////////////
!
!        AUXILIAR SUBROUTINES
!        --------------------
! 
!////////////////////////////////////////////////////////////////////////
!
      logical function HexMesh_FindPointWithCoords(self, x, eID, xi, optionalElements)
         implicit none
         class(HexMesh), intent(in)         :: self
         real(kind=RP),    intent(in)       :: x(NDIM)
         integer,          intent(out)      :: eID
         real(kind=RP),    intent(out)      :: xi(NDIM)
         integer, optional,intent(in)       :: optionalElements(:)
!
!        ---------------
!        Local variables
!        ---------------
!
         integer     :: op_eID
         logical     :: success

         HexMesh_FindPointWithCoords = .false.

         if ( present(optionalElements) ) then
            do op_eID = 1, size(optionalElements)
               if ( optionalElements(op_eID) .eq. -1 ) cycle
               associate(e => self % elements(optionalElements(op_eID)))
               success = e % FindPointWithCoords(x, xi) 
               if ( success ) then
                  eID = optionalElements(op_eID)
                  HexMesh_FindPointWithCoords = .true.
                  return 
               end if
               end associate
            end do
         end if      
         
         do eID = 1, self % no_of_elements
            associate(e => self % elements(eID))
            success = e % FindPointWithCoords(x, xi)
            if ( success ) then
               HexMesh_FindPointWithCoords = .true.
               return
            end if
            end associate
         end do

      end function HexMesh_FindPointWithCoords
!
!//////////////////////////////////////////////////////////////////////// 
!
!        CONSTRUCT ZONES
!        ---------------
! 
!//////////////////////////////////////////////////////////////////////// 
! 
      subroutine HexMesh_ConstructZones( self )
      implicit none
      class(HexMesh)          :: self

      call ConstructZones ( self % faces , self % zones )

      end subroutine HexMesh_ConstructZones
!
!///////////////////////////////////////////////////////////////////////
!
END MODULE HexMeshClass
      
