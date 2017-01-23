!
!////////////////////////////////////////////////////////////////////////
!
!      ReadInputFile.f90
!      Created: June 10, 2015 at 3:09 PM 
!      By: David Kopriva  
!
!////////////////////////////////////////////////////////////////////////
! 
      SUBROUTINE ReadInputFile (controlVariables)
         USE SMConstants
         USE FTValueDictionaryClass
         USE SharedBCModule
         USE mainKeywordsModule
         
         IMPLICIT NONE
!
!        ---------
!        Arguments
!        ---------
!
         TYPE(FTValueDictionary) :: controlVariables
!
!        ---------------
!        Local variables
!        ---------------
!
         CHARACTER(LEN=LINE_LENGTH) :: inputLine
         CHARACTER(LEN=LINE_LENGTH) :: keyword, keywordValue
         CHARACTER(LEN=LINE_LENGTH) :: boundaryName
         CHARACTER(LEN=LINE_LENGTH) :: boundaryType
         CHARACTER(LEN=LINE_LENGTH) :: boundaryValue
         CHARACTER(LEN=LINE_LENGTH) :: arg
         INTEGER                    :: numberOfBCs, k
         INTEGER                    :: ist
!
!        ---------------------------------------
!        External functions from FileReading.f90
!        ---------------------------------------
!
         REAL(KIND=RP)             , EXTERNAL    :: GetRealValue
         INTEGER                   , EXTERNAL    :: GetIntValue
         CHARACTER(LEN=LINE_LENGTH), EXTERNAL    :: GetStringValue, GetKeyword, GetValueAsString
         LOGICAL                   , EXTERNAL    :: GetLogicalValue
!
!        -----------------------------------------------
!        Read the input file.
!
!        we use dictionaries to store the input file 
!        parameters.
!        -----------------------------------------------
!
         CALL get_command_argument(1, arg)
         OPEN(UNIT=10,FILE=trim(arg))

         DO
            READ(10,'(A132)', IOSTAT = ist) inputLine
            IF(ist /= 0 .OR. inputLine(1:1) == '/') EXIT 
            IF ( inputLine(1:1) == "!" ) CYCLE ! Skip comments
            
            keyword      = ADJUSTL(GetKeyword(inputLine))
            keywordValue = ADJUSTL(GetValueAsString(inputLine))
            CALL toLower(keyword)
            CALL controlVariables % addValueForKey(keywordValue,TRIM(keyword))
            
            IF(keyword == numberOfBoundariesKey) THEN 
!
!              ---------------------------------------------------------------------------
!              We will store the type and values of the boundaries in dictionaries so that
!              we can associate a name of a boundary curve found in the mesh file with a
!              particular value and type of boundary conditions.
!              ---------------------------------------------------------------------------
!
               numberOfBCs = controlVariables%integerValueForKey(numberOfBoundariesKey)
               
               DO k = 1, numberOfBCs 
                  READ(10,*) boundaryName, boundaryValue, boundaryType
                  CALL toLower(boundaryName)
                  CALL toLower(boundaryType)
                  CALL bcTypeDictionary % addValueForKey(boundaryType, boundaryName)
                  CALL bcValueDictionary % addValueForKey(boundaryValue, boundaryName)
               END DO
            END IF
            
         END DO

         CLOSE(UNIT=10)

      END SUBROUTINE ReadInputFile
      
