IF EXISTS (SELECT * FROM sysobjects WHERE type = 'P' AND name = 'FindTableColumnDataMatches')
	BEGIN		
		DROP  Procedure  FindTableColumnDataMatches
	END

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[FindTableColumnDataMatches]
(	@strSearchTerm AS VARCHAR(1000) )
AS

/*******************************************************************
Author:  Jane Dallaway
Updates at: https://github.com/janedallaway/SQL-Server-Helper-Scripts
Documentation at: https://github.com/janedallaway/SQL-Server-Helper-Scripts
Date Created: January 24th 2008
Description: This procedure searches for @strSearchTerm amongst all text, ntext,
varchar, nvarchar, char and nchar columns in all tables.  If this is run against
a large database it will take a long time to complete

Modified:   add a comment here (date, who, comment)

Date        Author      Description
~~~~~~~     ~~~~~ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Usage:
      exec FindTableColumnDataMatches @strSearchTerm ='users'
                                       
 
*******************************************************************/

	SET NOCOUNT ON

	-- Variables
	DECLARE @tabSearchableColumns TABLE (TableName VARCHAR(100), ColumnName VARCHAR(100), Matches int)
	DECLARE @intCount INT
	DECLARE @intDataCount INT
	DECLARE @strTableName VARCHAR(100)
	DECLARE @strColumnName VARCHAR(100)
	DECLARE @strSQL NVARCHAR(1000) -- This must be an nvarchar to allow the sql to be passed in to sp_executesql

	-- Produce a list of columns (with their tablenames) 
	INSERT INTO @tabSearchableColumns
	SELECT TABLE_NAME,COLUMN_NAME, NULL
	FROM INFORMATION_SCHEMA.COLUMNS
	WHERE DATA_TYPE IN ('varchar', 'nvarchar', 'text', 'ntext', 'char', 'nchar')

	-- Get the number of possible places
	SELECT @intCount = COUNT(*) 
	FROM @tabSearchableColumns 
	WHERE Matches IS NULL

	-- Whilst there is still data to complete
	WHILE @intCount > 0
	BEGIN

		-- Get the top entry to work on now
		SELECT TOP 1 @strTableName = TableName, @strColumnName = ColumnName 
		FROM @tabSearchableColumns 
		WHERE Matches IS NULL
		ORDER BY TableName, ColumnName
		
		-- Build up the dynamic SQL statement
		SET @strSQL = 'SELECT @intDataCount = COUNT(*) FROM ' + @strTableName + ' WHERE ' + @strColumnName + ' LIKE ''%' + @strSearchTerm + '%'''

		-- Use sp_executesql to allow the variable to be returned out from the dynamic sql
		EXEC sp_executesql @strSQL, N'@intDataCount INT OUTPUT', @intDataCount OUTPUT 	
		
		-- Update the working set, to store the matches returned from the dynamic SQL
		UPDATE @tabSearchableColumns 
		SET Matches = @intDataCount 
		WHERE TableName = @strTableName 
		AND ColumnName = @strColumnName
		
		-- Reset the counter
		SELECT @intCount = COUNT(*) 
		FROM @tabSearchableColumns 
		WHERE Matches IS NULL
		
	END

	-- Display the results
	SELECT TableName, ColumnName, Matches 
	FROM @tabSearchableColumns
	WHERE Matches > 0

	RETURN(0)
GO
