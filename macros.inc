                ; Macros

                MACRO _PRINTAT x,y   ; Changes printig position to column x, line y
                LD B, y
                LD C, x
                CALL PrintAt
                ENDM

                MACRO _SETREG regID,value ; Sets ZXuno register at A to value at E
                LD E, value
                LD A, regID
                CALL SetZXUNOReg
                ENDM

                ; Same as previous but E is already set
                MACRO _SETREGB regID
                LD A, regID
                CALL SetZXUNOReg
                ENDM

                ; Gets ZXUno register
                MACRO _GETREG regID
                LD A, regID
                CALL GetZXUnoReg
                ENDM

                MACRO _WRITE string
                CALL PrintString        
                DB string, 0
                ENDM

                MACRO _BOX x, y, width, height
                LD B, y
                LD C, x
                LD D, width
                LD E, height
                CALL DrawBox
                ENDM

                MACRO _INVERSE mode
                LD A, mode
                CALL SetInverseMode
                ENDM

