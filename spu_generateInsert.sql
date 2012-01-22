IF EXISTS (SELECT * FROM sysobjects WHERE xtype = 'P' AND name = 'spu_GenerateInsert') 
BEGIN 
     DROP PROCEDURE spu_GenerateInsert 
END 
GO 

CREATE PROCEDURE [dbo].[spu_GenerateInsert] 
     @tableSchema varchar(128) = 'dbo', -- used to specify the tableschema, if null or empty string defaults to dbo 
     @table varchar(128), -- used to specify the table to generate data for 
     @generateGo bit = 0, -- used to allow GO statements to separate the insert statements 
     @restriction varchar(1000) = '', -- used to allow the data set to be restricted, no need for the where clause but can use syntax as 'columna = 1' 
     @producesingleinsert bit = 0, -- used to switch the ability to produce multiple insert statements (default) or one statement using UNION SELECT 
     @debug bit = 0, -- used to allow debugging to be turned on to the stored procedure - in case of queries 
     @GenerateOneLinePerColumn bit = 0, -- used to display the columns and data on separate lines 
     @GenerateIdentityColumn bit = 1 -- used to prevent the identity columns from being scripted 
AS 
/******************************************************************************* 
Original Author: Keith E Kratochvil 

This version: Jane Dallaway 

Available from: http://docs.google.com/Doc?docid=0AfAkC4ZdTI9tZGNwc3d4amNfNmZ4enFubmNz&hl=en_GB 

Documentation at: http://jane.dallaway.com/tag/spu_generateinsert 

Date Created: March 16, 2000 

Description: This procedure takes the data from a table and turns it into  
an insert statement. 

CAUTION!!! If you run this on a large table be prepared to wait a while! 

Modified:   add a comment here (date, who, comment) 

Date        Name  Description 
~~~~~~~     ~~~~~ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
07/11/03    Jane  Added a @generateGO parameter to allow selection 
07/11/03    Jane  This procedure has an issue with NULLs.... 
07/11/03    Jane  Deal with Identities 
07/11/03    Jane  Wrap all tablenames and columns with [ and ] 
15/12/03    Jane  For DateTimes covert as style 1 - to allow for mm/dd/yyy 
16/12/03    Jane  Get rid of rowcount 
18/12/03    Jane  Prevent single field tables having that field displayed twice 
06/07/04    Jane  Large money values get separeted with a comma - so specify convert 
                  with 0 rather than 1          
31/05/05    Jane  Added default for GenerateGo and added ability to generate 
                  Inserts for selected records based on the restriction 
03/01/08    Jane  Updated to cope with text and ntext.  It converts to VARCHAR(8000) to allow quote escaping 
                  Also copes with Nulls much better now. 
07/01/08    Jane  Now handles guids 
07/01/08    Jane  Forced collation to use database_default as was causing an error in some circumstances 
15/01/08    Jane  Dave reported issue with image column types as a comment on my blog 
                  http://jane.dallaway.com/blog/2007/11/generate-sql-insert-statement-from.html#c9038036788352783369 
                  So, ensured that all column types either work, or replace with NULL and add warning 
23/01/08    Jane  Ignore calculated columns.  Can't migrate the data, so remove from the INSERT 
                  Implemented a suggestion from Jon Green - 4R Systems Inc left on my blog post at 
                  http://jane.dallaway.com/blog/2007/11/generate-sql-insert-statement-from.html#c2055936172890486440 
                  to allow a choice of separate insert statements or a single statement using the UNION SELECT syntax. 
                  New parameter @producesingleinsert used.  When this is set to 0 it produces separate INSERT statements. 
                  When set to 1 it produces a single statment using UNION SELECT 
20/08/08 Jane     New parameter @GenerateOneLinePerColumn added as suggested by Christian via comment on my blog post at 
                  http://jane.dallaway.com/blog/2007/11/generate-sql-insert-statement-from.html?showComment=1219174920000#c6992035307857457643 
                  Also made all string variables varchar(max).  This means it no longer works on SQL 2000 - but to make it do so is just a case of 
                  putting all varchar(max) to varchar(8000) 
07/01/09 Jane     New parameter @GenerateIdentityColumns added as suggestion by James Bradshaw to enable identity columns to not be scripted 
                  and therefore rely on the database to populate the identities from scratch 
16/02/09 Jane     Continuation of work started on 20/08/08 - all remaining VARCHAR(8000)s removed and replaced with VARCHAR(max).  So, no longer 
                  an issue with text columns unless it is SQL Server 2000, in which case this stored procedure will need to have been updated.   
16/04/09 Jane     Add checking to see if the table specified actually exists - user error on my case when using the procedure 
17/04/09 Jane     Changed @tabledata to be nvarchar rather than varchar to allow for unicode                   
                  Added checking for data exceeding 8000 bytes and split the data based on CHAR(13) if this situation is seen.   
                  This won't resolve it in all cases, and if it doesn't then a warning is displayed at the bottom of the generated code 
08/06/09 Jane     All strings are now output as N'«data»' rather than '«data»' to cope with extended character sets 
24/09/10 James  Added support to specify the db schema. 
24/09/10 Jane  Cope with . in the table name, forced the default for schema to be dbo via parameter 

Known Issues:      
     1) BLOBs can't be output 

Usage: 
     exec spu_GenerateInsert @tableSchema='dbo', @table ='users', @generateGo=0, @restriction='columna = x', @producesingleinsert=0, @debug=0, @GenerateOneLinePerColumn=0, @GenerateIdentityColumn=0 
                 

Version: 
     This version has been tested on SQL Server 2005.  To make this work on SQL Server 2000, replace all instances of VARCHAR(max) with VARCHAR(8000).  This will limit  
     the ability of export of text and XML columns to 8000 characters 

*******************************************************************************/ 
--Variable declarations 
DECLARE @InsertStmt varchar(max) -- change this to be (8000) for SQL Server 2000 
DECLARE @Fields varchar(max) -- change this to be (8000) for SQL Server 2000 
DECLARE @SelList varchar(max) -- change this to be (8000) for SQL Server 2000 
DECLARE @Data varchar(max) -- change this to be (8000) for SQL Server 2000 
DECLARE @ColName varchar(128) 
DECLARE @IsChar tinyint 
DECLARE @FldCounter int 
DECLARE @TableData nvarchar(max) -- change this to be (8000) for SQL Server 2000 

-- added by Jane - 07/11/03 
DECLARE @bitIdentity BIT 

-- added by Jane 03/01/08 
DECLARE @bitHasEncounteredText BIT 
SET @bitHasEncounteredText = 0 

-- added by Jane 15/01/08 
DECLARE @bitHasEncounteredImage BIT 
SET @bitHasEncounteredImage = 0 
DECLARE @bitHasEncounteredBinary BIT 
SET @bitHasEncounteredBinary = 0 
DECLARE @bitHasEncounteredXML BIT 
SET @bitHasEncounteredXML = 0 
   
-- added by Jane - 23/01/08 
DECLARE @bitInsertStatementPrinted BIT 
SET @bitInsertStatementPrinted = 0 

-- added by Jane - 17/04/09 - To try and cope with bits of data which are greater than 8000 bytes 
DECLARE @bitDataExceedMaxPrintLength BIT 
SET @bitDataExceedMaxPrintLength = 0 
DECLARE @cintMaximumSupportedPrintByteCount INT 
SET @cintMaximumSupportedPrintByteCount = 8000 -- based on SQL Server 2005 
DECLARE @statementToOutput NVARCHAR(max) -- change this to be (8000) for SQL Server 2000 
DECLARE @NextCR INT -- used to split the output up into smaller chunks - look for carriage returns/line feeds and break into separate print statements 
DECLARE @statementsToOutput TABLE (Id INT IDENTITY(1,1), singleStatement NVARCHAR (max) ) -- change this to be (8000) for SQL Server 2000 
DECLARE @id INT 
DECLARE @singleStatement NVARCHAR(max) -- change this to be (8000) for SQL Server 2000 
DECLARE @loop INT 

-- added by Jane - 16/12/03 
SET NOCOUNT OFF 

-- added by Jane - 16/04/09 - check for table existance 
-- AND TABLE_SCHEMA = @tableSchema added by James - 24/09/2010 
IF EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @table AND TABLE_SCHEMA = @tableSchema) 
BEGIN 
     -- added by Jane - 16/04/2009 - Show details of table being generated, and date/time 
     PRINT REPLICATE('-', 37 + LEN(@table) + LEN(CONVERT(VARCHAR,GETDATE(),120)))           
     PRINT '-- Script generated for table [' +@TableSchema +'].[' + @table + '] on ' + CONVERT(VARCHAR,GETDATE(),120) + ' --' 
     PRINT REPLICATE('-', 37 + LEN(@table) + LEN(CONVERT(VARCHAR,GETDATE(),120))) 

     -- added by Jane - 07/11/03 
     SELECT @bitIdentity = OBJECTPROPERTY(OBJECT_ID(TABLE_SCHEMA+'.'+TABLE_NAME), 'TableHasIdentity') 
     FROM INFORMATION_SCHEMA.TABLES 
     WHERE TABLE_Name = @table  
     AND TABLE_SCHEMA = @tableSchema --added by James - 24/09/2010 
       
     -- added by Jane - 03/01/08 
     PRINT '-- ** Start of Inserts ** --' 
     PRINT '' 
       
     -- added by Jane - 07/11/03 
     -- AND @GenerateIdentityColumn = 1 added by Jane - 07/01/09 
     IF @bitIdentity = 1 AND @GenerateIdentityColumn = 1 
     BEGIN 
           PRINT 'SET IDENTITY_INSERT ['+@tableSchema +'].[' + @table + '] ON ' 
     END 
       
     --initialize some of the variables 
     -- updated by Jane 20/08/08 added one line per column functionality as per Christian's suggestion 
     -- updated by James 24/09/2010 tableschema 
     SELECT @InsertStmt = 'INSERT INTO ['+@tableSchema +'].[' + @Table + '] '+ CASE WHEN @GenerateOneLinePerColumn = 1 THEN CHAR(13) ELSE '' END + '(' + CASE WHEN @GenerateOneLinePerColumn = 1 THEN CHAR(13) ELSE '' END, 
           @Fields = '', 
           @Data = '', 
           @SelList = 'SELECT ', 
           @FldCounter = 0 
       
     --create a cursor that loops through the fields in the table 
     --and retrieves the column names and determines the delimiter type that the 
     --field needs 
     DECLARE CR_Table CURSOR FAST_FORWARD FOR 
            
           SELECT COLUMN_NAME, 
                  'IsChar' = CASE 
                  WHEN DATA_TYPE in ('int', 'money', 'decimal', 'tinyint', 'smallint' ,'numeric', 'bit', 'bigint', 'smallmoney', 'float','timestamp') THEN 0 
                  WHEN DATA_TYPE in ('char', 'varchar', 'nvarchar','uniqueidentifier', 'nchar') THEN 1 
                  WHEN DATA_TYPE in ('datetime', 'smalldatetime') THEN 2 
                  WHEN DATA_TYPE in ('text', 'ntext') THEN 3 
                  WHEN DATA_TYPE in ('image') THEN 4 -- added by Jane - 15/01/08 
                  WHEN DATA_TYPE in ('binary', 'varbinary') THEN 5 -- added by Jane - 15/01/08 
                  WHEN DATA_TYPE in ('sql_variant') THEN 6 -- added by Jane - 15/01/08 - Force to be converted as varchars 
                  WHEN DATA_TYPE in ('xml') THEN 7 -- added by Jane - 15/01/08 
                  ELSE 9 
           END 
           FROM INFORMATION_SCHEMA.COLUMNS c WITH (NOLOCK) 
           INNER JOIN syscolumns sc WITH (NOLOCK) 
           ON c.COLUMN_NAME = sc.name 
           INNER JOIN sysobjects so WITH (NOLOCK) 
           ON sc.id = so.id 
           AND so.name = c.TABLE_NAME 
           WHERE table_name = @table 
           AND TABLE_SCHEMA = @tableSchema -- added by James - 24/09/2010 
           AND DATA_TYPE «»'timestamp' 
           AND sc.IsComputed = 0       
           AND 1 =  
               CASE @GenerateIdentityColumn  
               WHEN 1 -- When we want the identity columns to be generated, then always include the column 
               THEN 1  
               ELSE  
                    CASE COLUMNPROPERTY(object_id(TABLE_SCHEMA+'.'+TABLE_NAME), COLUMN_NAME, 'IsIdentity') -- Check if the column has the property IsIdentity 
                    WHEN 1 -- If it does 
                    THEN 0 -- don't include this column 
                    ELSE 1 -- otherwise include this column 
                    END 
               END 
           ORDER BY ORDINAL_POSITION 
           FOR READ ONLY 
           OPEN CR_Table 
       
           FETCH NEXT FROM CR_Table INTO @ColName, @IsChar 
       
     WHILE (@@fetch_status «» -1) 
     BEGIN 
       
           IF @IsChar = 3 
                  SET @bitHasEncounteredText = 1            
       
           -- added by Jane - 15/01/08 
           IF @IsChar = 4 
                  SET @bitHasEncounteredImage = 1 
           IF @IsChar = 5 
                  SET @bitHasEncounteredBinary = 1 
       
           IF (@@fetch_status «» -2) 
           BEGIN 
       
                  -- Updated by Jane - 15/01/08 - cope with xml, image, binary, varbinary etc 
                  -- Updated by Jane - 03/01/08 to cope with text and ntext - converts to VARCHAR(8000) to allow quote escaping 
                  -- Special case for first field 
                  IF @FldCounter = 0 
                  BEGIN 
                          SELECT @Fields =  @Fields + '[' + @ColName + ']' + ', ' 
                          -- Updated by Jane - 08/06/09 - prefix string with N to cope with extended character sets                           
                          SELECT @SelList =  CASE @IsChar 
                                 WHEN 1 THEN @SelList +  ' ISNULL(''N'''''' + REPLACE(['+  @ColName + '],'''''''', '''''''''''') + '''''''' ,''NULL'')  ' + ' COLLATE database_default + ' 
                                 WHEN 2 THEN @SelList +  ' ISNULL(''N'''''' + CONVERT(varchar(20),[' + @ColName + ']) + '''''''',''NULL'') ' + ' COLLATE database_default + ' 
                                 WHEN 3 THEN @SelList +  ' ISNULL(''N'''''' + REPLACE(CONVERT(VARCHAR(max),['+  @ColName + ']),'''''''', '''''''''''')+  '''''''' ,''NULL'')  '+ ' COLLATE database_default + ' 
                                 WHEN 4 THEN @SelList + '''NULL''' + ' COLLATE database_default + ' 
                                 WHEN 5 THEN @SelList + '''NULL''' + ' COLLATE database_default + ' 
                                 WHEN 6 THEN @SelList +  ' ISNULL(''N'''''' + REPLACE(CONVERT(VARCHAR(max),['+  @ColName + ']),'''''''', '''''''''''')+  '''''''' ,''NULL'')  '+ ' COLLATE database_default + ' 
                                 WHEN 7 THEN @SelList +  ' ISNULL(''N'''''' + REPLACE(CONVERT(VARCHAR(max),['+  @ColName + ']),'''''''', '''''''''''')+  '''''''' ,''NULL'')  '+ ' COLLATE database_default + ' 
                                 ELSE @SelList + 'ISNULL(CONVERT(varchar(2000),['+@ColName + '],0),''NULL'')' + ' COLLATE database_default + ' 
                                 END 
                          SELECT @FldCounter = @FldCounter + 1 
                          SET @SelList = @Sellist 
                          FETCH NEXT FROM CR_Table INTO @ColName, @IsChar 
                  END 
       
                  -- Updated by Jane - 15/01/08 - cope with xml, image, binary, varbinary etc 
                  -- Updated by Jane - 03/01/08 to cope with NULL replacements            
                  -- Updated by Jane - 03/01/08 to cope with text and ntext - converts to VARCHAR(8000) to allow quote escaping 
                  -- Updated by Jane - 18/12/03 to prevent single field tables having that field displayed twice 
                  -- Updated by Jane - 20/08/08 to incorporate the @GenerateOneLinePerColumn parameter suggested by Christian 
                  IF @@fetch_status «» -1 
                  BEGIN 
                          SELECT @Fields =  @Fields + '[' + @ColName + ']' + ', ' 
                          -- Updated by Jane - 08/06/09 - prefix string with N to cope with extended character sets 
                          SELECT @SelList =  CASE @IsChar 
                                 WHEN 1 THEN @SelList +  ''',''' + CASE WHEN @GenerateOneLinePerColumn = 1 THEN ' + CHAR(13) ' ELSE '' END + ' + ' +  ' ISNULL(''N'''''' + REPLACE(['+  @ColName + '],'''''''', '''''''''''' ) +  '''''''',''NULL'') ' + ' COLLATE database_default + ' 
                                 WHEN 2 THEN @SelList + ''',''' + CASE WHEN @GenerateOneLinePerColumn = 1 THEN  ' + CHAR(13) ' ELSE '' END + ' + '  +  'ISNULL(''N'''''' + CONVERT(varchar(20),['+ @ColName + '])+ '''''''',''NULL'') ' + ' COLLATE database_default + ' 
                                 WHEN 3 THEN @SelList +  ''',''' + CASE WHEN @GenerateOneLinePerColumn = 1 THEN ' + CHAR(13) ' ELSE '' END + ' + ' +  ' ISNULL(''N'''''' + REPLACE(CONVERT(VARCHAR(max),['+  @ColName + ']),'''''''', '''''''''''' )+  '''''''',''NULL'')  ' + ' COLLATE database_default + ' 
                                 WHEN 4 THEN @SelList + ''',''' + CASE WHEN @GenerateOneLinePerColumn = 1 THEN  ' + CHAR(13) ' ELSE '' END + ' + ' +  '''NULL''' + ' COLLATE database_default + ' 
                                 WHEN 5 THEN @SelList + ''',''' + CASE WHEN @GenerateOneLinePerColumn = 1 THEN  ' + CHAR(13) ' ELSE '' END + ' + ' +  '''NULL''' + ' COLLATE database_default + ' 
                                 WHEN 6 THEN @SelList + ''',''' + CASE WHEN @GenerateOneLinePerColumn = 1 THEN  ' + CHAR(13) ' ELSE '' END + ' + ' +   ' ISNULL(''N'''''' + REPLACE(CONVERT(VARCHAR(max),['+  @ColName + ']),'''''''', '''''''''''')+  '''''''' ,''NULL'')  '+ ' COLLATE database_default + ' 
                                 WHEN 7 THEN @SelList + ''',''' + CASE WHEN @GenerateOneLinePerColumn = 1 THEN  ' + CHAR(13) ' ELSE '' END + ' + ' +   ' ISNULL(''N'''''' + REPLACE(CONVERT(VARCHAR(max),['+  @ColName + ']),'''''''', '''''''''''')+  '''''''' ,''NULL'')  '+ ' COLLATE database_default + ' 
                                 ELSE @SelList  + ''',''' + CASE WHEN @GenerateOneLinePerColumn = 1 THEN  ' + CHAR(13) ' ELSE '' END + ' + ' + ' ISNULL(CONVERT(varchar(2000),['+@ColName + '],0),''NULL'')' + ' COLLATE database_default + ' 
                          END   
                  END 
           END   
       
           FETCH NEXT FROM CR_Table INTO @ColName, @IsChar 
     END 
       
     CLOSE CR_Table 
     DEALLOCATE CR_Table 
       
     SELECT @Fields =  SUBSTRING(@Fields, 1,(len(@Fields)-1)) 
       
     SELECT @SelList =  SUBSTRING(@SelList, 1,(len(@SelList)-1)) 
     SELECT @SelList = @SelList + ' FROM ' +@TableSchema +'.[' + @table + ']' 
       
     IF LEN(@restriction) » 0 
     BEGIN 
           SELECT @SelList = @SelList + ' WHERE ' + @restriction 
     END 
       
     -- updated by Jane 20/08/08 added one line per column functionality as per Christian's suggestion 
     SELECT @InsertStmt = @InsertStmt + CASE WHEN @GenerateOneLinePerColumn = 1 THEN REPLACE(@Fields,', ',',' + CHAR(13)) ELSE @Fields END + CASE WHEN @GenerateOneLinePerColumn = 1 THEN CHAR(13) ELSE '' END + ')' 
       
     --for debugging purposes... 
     IF @Debug = 1 
     BEGIN 
           PRINT '*** DEBUG INFORMATION - THIS IS THE SELECT STATEMENT BEING RUN *** ' 
           PRINT @sellist 
           PRINT '*** END DEBUG ***' 
     END 
       
     -- added by Jane - 16/12/03 
     SET NOCOUNT ON 
       
     --now we need to create and load the temp table that will hold the data 
     --that we are going to generate into an insert statement 
       
     CREATE TABLE #TheData (TableData VARCHAR(max)) -- change this to be (8000) for SQL Server 2000 
     INSERT INTO #TheData (TableData) EXEC (@SelList) 
       
     --Cursor through the data to generate the INSERT statement / VALUES/SELECT/UNION SELECT clause 
     DECLARE CR_Data CURSOR FAST_FORWARD FOR SELECT TableData FROM #TheData FOR 
     READ ONLY 
     OPEN CR_Data 
     FETCH NEXT FROM CR_Data INTO @TableData 
       
           WHILE (@@fetch_status «» -1) 
           BEGIN 
                 IF (@@fetch_status «» -2) 
                 BEGIN                                             

                       -- Updated by Jane 17/04/09 instead of printing at this point, store the output in a @statementToOutput variable.  This allows us to try and split it to  
                       -- to print within the 8000 byte limit imposed by the PRINT function  
                       -- Updated by Jane 23/01/08 after suggestion posted to blog at http://jane.dallaway.com/blog/2007/11/generate-sql-insert-statement-from.html#c2055936172890486440 
                       IF (@producesingleinsert = 1 ) 
                              IF (@bitInsertStatementPrinted = 0) 
                              BEGIN 
SET @statementToOutput = @InsertStmt + char(13) + 'SELECT ' + @TableData                                     
                                    SET @bitInsertStatementPrinted = 1 
                              END 
                              ELSE 
                              BEGIN 
SET @statementToOutput = 'UNION SELECT ' + @TableData 
                              END 
                       ELSE 
                       BEGIN 
                              -- updated by Jane 20/08/08 added one line per column functionality as per Christian's suggestion 
                              SET @statementToOutput =  @InsertStmt + CASE WHEN @GenerateOneLinePerColumn = 1 THEN CHAR(13) ELSE '' END + 'VALUES ' + + CASE WHEN @GenerateOneLinePerColumn = 1 THEN CHAR(13) ELSE '' END + '(' + CASE WHEN @GenerateOneLinePerColumn = 1 THEN CHAR(13) ELSE '' END + @TableData + CASE WHEN @GenerateOneLinePerColumn = 1 THEN CHAR(13) ELSE '' END + ')' + CHAR(13) 
                       END 
       
                       -- Added by Jane - 17/04/09 - check for length of @statementToOutput 
                       -- if it exceeds the maximum length, then lets attempt to split it on CRs as these will be done via separate PRINT statements 
                       IF DATALENGTH(@statementToOutput) » @cintMaximumSupportedPrintByteCount                                                                                                                      
                       BEGIN                                                       

                           -- Break the @statementToOutput based on CHAR(13) and put separate data values into @statementsToOutput table 

                           -- Get rid of double line breaks 
                           -- Replace CHAR(10) with CHAR(13) 
                           SET @statementToOutput = REPLACE(@statementToOutput,CHAR(10),CHAR(13)) 
                           -- Replace CHAR(13)+CHAR(13) with CHAR(13) 
                           SET @statementToOutput = REPLACE(@statementToOutput,CHAR(13)+CHAR(13),CHAR(13)) 

                           SET @NextCR = Charindex(CHAR(13),@statementToOutput) 
                           WHILE @NextCR  » 0 
                           BEGIN 
                                
                               INSERT INTO @statementsToOutput VALUES(LEFT(@statementToOutput,@NextCR - 1)) 

                               SET @statementToOutput = Right(@statementToOutput,Len(@statementToOutput) - @NextCR) 
                               SET @NextCR = Charindex(CHAR(13),@statementToOutput) 
                           END                               
                           INSERT INTO @statementsToOutput VALUES(@statementToOutput)                                                                     

                           -- Output the statements line by line 
   SET @loop = 1 
   SET @id = -1 

   WHILE @loop = 1 
   BEGIN 
                               SELECT TOP 1 @id = Id, @singleStatement = singlestatement 
                               FROM @statementsToOutput 
                               WHERE id » @id 
                               ORDER BY Id 

                               SET @loop = @@ROWCOUNT 

                               IF @loop = 0 
                                    BREAK 

                               -- No guarantee that we still don't exceed the limits, but should have more of a chance of avoiding them 
                               IF DATALENGTH(@singleStatement) » @cintMaximumSupportedPrintByteCount 
                               BEGIN 
                                    SET @bitDataExceedMaxPrintLength = 1 
                                    SELECT @singleStatement                            
                               END 

                               PRINT @singleStatement 
   END     
                       END     
                       ELSE 
                       BEGIN  
                           -- Don't need to worry, we haven't exceeded the 8000 byte limit so just print it 
   PRINT @statementToOutput  
                       END 

                       IF @generateGo = 1 
                       BEGIN 
                              PRINT 'GO' 
                       END 
                 END 
                 FETCH NEXT FROM CR_Data INTO @TableData 
           END 
     CLOSE CR_Data 
     DEALLOCATE CR_Data 
       
     -- added by Jane - 07/11/03 
     -- AND @GenerateIdentityColumn = 1 added by Jane - 07/01/09 
     IF @bitIdentity = 1 AND @GenerateIdentityColumn = 1 
     BEGIN 
           PRINT 'SET IDENTITY_INSERT [' + @table + '] OFF ' 
     END 
       
     -- added by Jane - 03/01/08 
     PRINT '-- ** End of Inserts ** --' 
       
     IF @bitHasEncounteredImage = 1 
     BEGIN 
           PRINT '-- ** WARNING: There is an image column in your table which has not been migrated - this has been replaced with NULL.  You will need to do this by hand.  Images are not supported by this script at this time.  ** --' 
     END 
       
     -- added by Jane - 15/01/08 
     IF @bitHasEncounteredBinary = 1 
     BEGIN 
           PRINT '-- ** WARNING: There is a binary or varbinary column in your table which has not been migrated - this has been replaced with NULL.  You will need to do this by hand.  Binary and VarBinary are not supported by this script at this time.  ** --' 
     END 
       
     -- 16/02/09 - These checks are only required if the database is SQL Server 2000 
     DECLARE @Version VARCHAR(100) 
     SELECT @Version = @@VERSION 
     IF PATINDEX('%8.00%',@Version) » 0 
     BEGIN 
          IF @bitHasEncounteredXML = 1 
          BEGIN 
                PRINT '-- ** WARNING: This will convert any ''xml'' data to be ''varchar(8000)'' ** --' 
          END 
            
          -- added by Jane - 03/01/08 
          IF @bitHasEncounteredText = 1  
          BEGIN 
                PRINT '-- ** WARNING: This will convert any ''text'' or ''ntext'' data to be ''varchar(8000)'' ** --' 
          END 
     END 

     IF @bitDataExceedMaxPrintLength = 1 
     BEGIN 
          PRINT '-- ** WARNING: The data length for at least one row exceeds '+ CONVERT(VARCHAR(6),@cintMaximumSupportedPrintByteCount) + ' bytes.  The PRINT command is limited to ' + CONVERT(VARCHAR(6),@cintMaximumSupportedPrintByteCount) + ' bytes (for more information see http://msdn.microsoft.com/en-us/library/ms176047.aspx).  Do not trust this data. ** --' 
     END 
END 
ELSE 
BEGIN 

     -- added by Jane - 16/04/2009 - Warn user that table doesn't exist 
     PRINT REPLICATE('-', 43 + LEN(@table))      
     PRINT '-- Table [' + @TableSchema + '].[' + @table + '] doesn''t exist on this database --' 
     PRINT REPLICATE('-', 43 + LEN(@table)) 

END  
RETURN (0)