USE [master]
GO
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'spu_compareprocedures')
BEGIN
	DROP PROCEDURE spu_compareprocedures
END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--------------------------------------------------------------------------------------------
-- Name: spu_compareprocedures
-- 
-- Author: Jane Dallaway
--
-- Created: 15th April 2009
--
-- This file available at : http://jane.dallaway.com/downloads/SQL/spu_compareprocedures.sql
--
-- Documentation and updates at: http://jane.dallaway.com/blog/labels/spu_compareprocedures.html
--
--------------------------------------------------------------------------------------------
-- Modification History:
-- --------------------
-- 20090416	Jane	Added checking for procedure's existance
-- 20090417	Jane	Reworked the comma checking.  When no stored procedures specified, report
--					on all
-- 20090417	Jane	The INFORMATION_SCHEMA.ROUTINES.ROUTINE_DEFINITON column is limited to 
--					4000 characters, so only the first 4000 characters were being checked.
--					Updated to use syscomments instead to check the entire procedure
--
--------------------------------------------------------------------------------------------
-- Usage:
--		@db1 - must specify the name of the 1st database to use 
--		@db2 - must specify the name of the 2nd database to use
--		@proceduresToCompare - used to restrict the objects being compared - 
--							        should be a comma separated list.  If not supplied checks
--									all procedures and functions in both databases
--		@displayOnlyDifferent - show only different stored procedures/functions - defaults to this, to
--								display the same ones as well set this to 0.
--								Always shows any errors regardless of this setting
--	    @debug - can be used to get extra information from the stored procedure - mainly SQL used
--				 internally to allow for debugging of this procedure
--
-- Example:
--		spu_compareprocedures @db1 = 'MyMasterDatabase', @db2 = 'MyOtherDatabase', @proceduresToCompare='spu_generateinsert,spu_compareprocedures', @displayOnlyDifferent=1, @debug=0
--
-- Output:
--		is produced as text in the Messages window of Management Studio/Query analyser
--
-- Testing:
--		tested on SQL Server 2005 only
--
--------------------------------------------------------------------------------------------
CREATE PROC [dbo].[spu_compareprocedures]
(
	@db1          VARCHAR(128),         		   	
	@db2			 VARCHAR(128),	
	@proceduresToCompare VARCHAR(8000) = '',  	
	@displayOnlyDifferent BIT = 1,	   
	@debug        BIT  = 0
)
AS
BEGIN

	SET NOCOUNT  ON
	SET ANSI_WARNINGS  ON
	SET ANSI_NULLS  ON

	-- Variable declarations
	DECLARE  @sql VARCHAR(8000)
	DECLARE  @loop INT   
	DECLARE  @name SYSNAME
	DECLARE  @Comment VARCHAR(255)
	DECLARE  @NextCommaPos INT 	
	DECLARE  @database SYSNAME

	-- Set up constants - used for the comment fields
	DECLARE @c_ProcedureMissing VARCHAR(50)
	SET  @c_ProcedureMissing = 'missing'
	DECLARE @c_ProcedureDifferent VARCHAR(50)
	SET @c_ProcedureDifferent = 'different'
	DECLARE @c_ProcedureSame VARCHAR(50)
	SET @c_ProcedureSame = 'same'

	-- Set up tables to store comparison objects and outputs
	IF EXISTS (SELECT 1 FROM tempdb.dbo.sysobjects WHERE  name LIKE '#proceduresToCompare%')
	BEGIN
		DROP TABLE #proceduresToCompare
	END

	CREATE TABLE #proceduresToCompare (ObjectName sysname)

	IF EXISTS (SELECT 1 FROM tempdb.dbo.sysobjects WHERE  name LIKE '#Results%')
	BEGIN
		DROP TABLE #Results
	END

	CREATE TABLE #Results (ObjectName sysname, Comment VARCHAR(255), DatabaseName SYSNAME NULL) 
 
	-- Tidy up the input parameters
	SET @db1 = Rtrim(Ltrim(@db1))
	SET @db2 = Rtrim(Ltrim(@db2))
	IF LEN(@proceduresToCompare) > 0
	BEGIN
		SET @proceduresToCompare = REPLACE(@proceduresToCompare,', ',',')
		SET @proceduresToCompare = REPLACE(@proceduresToCompare,' ,',' ,')
	END
                          
	PRINT REPLICATE ('*', DATALENGTH(@db1) + DATALENGTH(@db2) + 35)
	PRINT '  Comparing databases ' + @db1 + ' and ' + @db2
	PRINT '  Objects: '
	PRINT REPLICATE(' ',5) + CASE WHEN DATALENGTH(@proceduresToCompare) = 0 THEN ' ALL stored procedures in both databases - MAY TAKE A WHILE' ELSE REPLACE(@proceduresToCompare,',',CHAR(10)+REPLICATE(' ',5)) END 
	PRINT REPLICATE ('*', DATALENGTH(@db1) + DATALENGTH(@db2) + 35)

	IF @debug = 1
		PRINT 'DEBUG: Populating #proceduresToCompare' 

	IF @proceduresToCompare  <> ''
	BEGIN

		SET @NextCommaPos = Charindex(',',@proceduresToCompare)
		WHILE @NextCommaPos > 0
		BEGIN

			INSERT INTO #proceduresToCompare VALUES(LEFT(@proceduresToCompare,@NextCommaPos - 1))

			SET @proceduresToCompare = RIGHT(@proceduresToCompare,LEN(@proceduresToCompare) - @NextCommaPos)

			SET @NextCommaPos = Charindex(',',@proceduresToCompare)

		END
		INSERT INTO #proceduresToCompare VALUES(@proceduresToCompare)		
	END	
	ELSE
	BEGIN
		-- Check all stored procedures in either database
		-- Populate with @db1 procedures
		SET @sql = 'INSERT INTO #proceduresToCompare (ObjectName) SELECT ROUTINE_NAME FROM ' + @db1 + '.INFORMATION_SCHEMA.ROUTINES'
			
		IF @debug = 1
			PRINT 'DEBUG: SQL is - ' + @sql

		EXEC (@sql)

		-- Populate with @db2 procedures which aren't already in #proceduresToCompare
		SET @sql = 'INSERT INTO #proceduresToCompare (ObjectName) SELECT ROUTINE_NAME FROM ' + @db2 + '.INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME NOT IN (SELECT ROUTINE_NAME FROM #proceduresToCompare)'
			
		IF @debug = 1
			PRINT 'DEBUG: SQL is - ' + @sql

		EXEC (@sql)

	END

	IF EXISTS (SELECT 1 FROM #proceduresToCompare)
	BEGIN

		SET @Loop = 1
		SET @Name = ''

		WHILE @Loop = 1
		BEGIN

			SELECT TOP 1 @Name = ObjectName
			FROM #proceduresToCompare
			WHERE ObjectName > @Name
			ORDER BY ObjectName

			SET @Loop = @@ROWCOUNT

			IF @Loop = 0
				BREAK

			SET @sql = 'IF NOT EXISTS (SELECT 1 FROM ' + @db1 + '.INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = ''' + @Name + ''') BEGIN INSERT INTO #Results (ObjectName, Comment, DatabaseName) VALUES (''' + @name + ''',''' + @c_ProcedureMissing + ''',''' + @db1 + ''') END'
			
			IF @debug = 1
				PRINT 'DEBUG: SQL is - ' + @sql

			EXEC (@sql)
		
			SET @sql = 'IF NOT EXISTS (SELECT 1 FROM ' + @db2 + '.INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = ''' + @Name + ''') BEGIN INSERT INTO #Results (ObjectName, Comment, DatabaseName) VALUES (''' + @name + ''',''' + @c_ProcedureMissing + ''',''' + @db2 + ''') END'
			
			IF @debug = 1
				PRINT 'DEBUG: SQL is - ' + @sql

			EXEC (@sql)

			-- INFORMATION_SCHEMA.ROUTINES only stores first 4000 characters of the routine, so use the old syscomments
			-- table to get the contents to ensure true comparison
			SET @sql =	'DECLARE @contents1 VARCHAR(MAX) '
			+	'DECLARE @contents2 VARCHAR(MAX) '
			+	'DECLARE @contentsloop INT '
			+	'DECLARE @currentcontents VARCHAR(Max) '
			+	'DECLARE @contentsrow INT '
			+	'SET @contentsloop = 1 '
			+	'SET @currentcontents = '''''
			+	'SET @contents1 = '''''
			+	'SET @contentsrow = 0'
			+	'WHILE @contentsloop = 1'
			+	'BEGIN'
			+	'	SELECT TOP 1 @currentcontents = sc.text, @contentsrow = sc.colid '
			+	'	FROM ' + @db1 + '.dbo.sysobjects so '
			+	'	INNER JOIN ' + @db1 + '.dbo.syscomments sc '
			+	'	ON so.id = sc.id '
			+	'	WHERE so.xtype = ''P'''
			+	'	AND so.name = ''' + @name + ''''
			+	'   AND sc.colid > @contentsrow'
			+	'	ORDER BY sc.colid	'
			+	'	SET @contentsloop = @@ROWCOUNT '
			+	'	IF @contentsloop = 0 '
			+	'		BREAK '
			+	'	SET @contents1 = @contents1 + @currentcontents '			
			+	'END '
			+	'SET @contentsloop = 1 '
			+	'SET @currentcontents = '''''
			+	'SET @contents2 = '''''
			+	'SET @contentsrow = 0'
			+	'WHILE @contentsloop = 1'
			+	'BEGIN'
			+	'	SELECT TOP 1 @currentcontents = sc.text, @contentsrow = sc.colid '
			+	'	FROM ' + @db2 + '.dbo.sysobjects so '
			+	'	INNER JOIN ' + @db2 + '.dbo.syscomments sc '
			+	'	ON so.id = sc.id '
			+	'	WHERE so.xtype = ''P'''
			+	'	AND so.name = ''' + @name + ''''
			+	'   AND sc.colid > @contentsrow'
			+	'	ORDER BY sc.colid	'
			+	'	SET @contentsloop = @@ROWCOUNT '
			+	'	IF @contentsloop = 0 '
			+	'		BREAK '
			+	'	SET @contents2 = @contents2 + @currentcontents '			
			+	'END '
			+	'INSERT INTO #Results (ObjectName, Comment) SELECT ''' + @Name + ''', CASE WHEN @contents1 = @contents2  THEN ''' + @c_ProcedureSame + ''' ELSE ''' + @c_ProcedureDifferent + ''' END '

			IF @debug = 1
				PRINT 'DEBUG: SQL is - ' + @sql

			EXEC (@sql)
		END
	END
	ELSE
	BEGIN
	
		IF @proceduresToCompare = '1=1'
		BEGIN
			PRINT 'No objects specified, please provide a parameter for @proceduresToCompare in the form of a comma separated list of procedure names'
		END
		ELSE
		BEGIN
			PRINT 'No objects found'
		END
	END
	
	--------------------------------------------------------------------------------------------
	-- Output errors
	--------------------------------------------------------------------------------------------
	
	IF EXISTS (SELECT 1 FROM #Results WHERE Comment = @c_ProcedureMissing)
	BEGIN

		PRINT ''
		PRINT REPLICATE('*',17)
		PRINT '**    ERRORS   **'
		PRINT REPLICATE('*',17)
		PRINT ''

		SET @Loop = 1
		SET @Name = ''
		SET @Comment = ''

		SELECT @Loop = COUNT(*)
		FROM #Results
		WHERE Comment = @c_ProcedureMissing
			
		WHILE @Loop > 0
		BEGIN  				

			SELECT TOP 1 @Name = ObjectName, @Comment = Comment, @database = DatabaseName
			FROM #Results
			WHERE Comment = @c_ProcedureMissing
			ORDER BY ObjectName

			IF @Debug = 1
				PRINT 'DEBUG : Outputting error information for ' + @name
			
			PRINT @Name + ' is ' + @comment + ' for ' + @database 
	
			DELETE FROM #Results
			WHERE ObjectName = @Name
			AND Comment = @Comment
			AND DatabaseName = @database
	
			SELECT @Loop = COUNT(*)
			FROM #Results
			WHERE Comment = @c_ProcedureMissing

		END
	END

	--------------------------------------------------------------------------------------------
	-- Output comparisons
	--------------------------------------------------------------------------------------------

	IF EXISTS (SELECT 1 FROM #Results)
	BEGIN

		PRINT ''
		PRINT REPLICATE('*',17)
		PRINT '** COMPARISONS **'
		PRINT REPLICATE('*',17)
		PRINT ''

		IF EXISTS (SELECT 1 FROM #Results WHERE Comment = CASE WHEN @displayOnlyDifferent = 1 THEN @c_ProcedureDifferent ELSE Comment END)
		BEGIN
			
			SET @Loop = 1
			SET @Name = ''
			SET @Comment = ''

			SELECT @Loop = COUNT(*)
			FROM #Results

			WHILE @Loop > 0
			BEGIN  				

				SELECT TOP 1 @Name = ObjectName, @Comment = Comment
				FROM #Results		
				ORDER BY ObjectName

				IF @Debug = 1
					PRINT 'DEBUG : Outputting information for ' + @name
				
				IF @displayOnlyDifferent = 0 OR @Comment = @c_ProcedureDifferent
					PRINT @Name + ' on ' + @db1 + ' and ' + @db2 + ' are ' + @Comment

				DELETE FROM #Results
				WHERE ObjectName = @Name
				AND Comment = @Comment

				SELECT @Loop = COUNT(*)
				FROM #Results
			END
		END
		ELSE
		BEGIN
			PRINT 'No differences found'
		END				
	END
	--------------------------------------------------------------------------------------------
	-- Clean up temporary tables
	--------------------------------------------------------------------------------------------
	IF EXISTS (SELECT 1 FROM   tempdb.dbo.sysobjects WHERE  name LIKE '#proceduresToCompare%')
	BEGIN
		DROP TABLE #proceduresToCompare
	END

	IF EXISTS (SELECT 1 FROM   tempdb.dbo.sysobjects WHERE  name LIKE '#Results%')
	BEGIN
		DROP TABLE #Results
	END

	RETURN
END