-- Set up Tables/Procedures for Timing Audits
 
IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'Timings')
BEGIN
 
	CREATE TABLE [dbo].[Timings]
	(
		[Code] NVARCHAR(10) NOT NULL,
		[Description] NVARCHAR(100),
		[ActionTime] DATETIME NOT NULL,
		[IsComplete] BIT DEFAULT(0)
		CONSTRAINT [PK_Timings] PRIMARY KEY CLUSTERED
		(
			[Code] ASC,
			[IsComplete] ASC
		) ON [PRIMARY]
	) ON [PRIMARY]
	END
GO
 
IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'up_RecordStart')
BEGIN
 
	DROP PROCEDURE [dbo].[up_RecordStart]
END
GO
 
CREATE PROCEDURE [dbo].[up_RecordStart]
( @Code NVARCHAR(10),
@Description NVARCHAR(100) = '')
-- @Code - Parameter used to uniquely identify this action
-- @Description - Parameter used to record a description for this action
-- ActionTime is auto-populated with GETDATE()
-- IsComplete is auto-populated with 0 to indicate this is not a completion
AS
 
	SET NOCOUNT ON
	SET XACT_ABORT ON  
	 
	BEGIN TRAN
	 
	BEGIN TRY
		INSERT INTO [dbo].[Timings]
		( [Code], [Description], [ActionTime], [IsComplete])
		VALUES
		( @Code, @Description, GETDATE(), 0)
		 
		COMMIT TRAN
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 2627
		PRINT 'ERROR: You hve already used the code ' + @Code + ' for timing purposes.  Please choose a different code and try again.'
		ELSE
		PRINT 'ERROR: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ' - ' + ERROR_MESSAGE()
		ROLLBACK TRAN
	END CATCH
GO
 
IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'up_RecordEnd')
BEGIN
 
	DROP PROCEDURE [dbo].[up_RecordEnd]
END
GO
 
CREATE PROCEDURE [dbo].[up_RecordEnd]
( @Code NVARCHAR(10))
-- @Code - Parameter used to uniquely identify this action
-- @Description is only populated at the start point, not at end point
-- ActionTime is auto-populated with GETDATE()
-- IsComplete is auto-populated with 1 to indicate this is completion
AS
 
	SET NOCOUNT ON
	SET XACT_ABORT ON  
	 
	BEGIN TRAN
	 
	BEGIN TRY
		INSERT INTO [dbo].[Timings]
		( [Code], [ActionTime], [IsComplete])
		VALUES
		( @Code, GETDATE(), 1)
		COMMIT TRAN
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 2627
		PRINT 'ERROR: You hve already used the code ' + @Code + ' for timing purposes.  Please choose a different code and try again.'
		ELSE
		PRINT 'ERROR: ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ' - ' + ERROR_MESSAGE()
	 
		ROLLBACK TRAN
	END CATCH
 
GO
 
IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'up_GetTimings')
BEGIN
 
	DROP PROCEDURE [dbo].[up_GetTimings]
END
GO
 
CREATE PROCEDURE [dbo].[up_GetTimings]
( @Code NVARCHAR(10) )
-- @Code - Parameter used to identify this action uniquely
-- Returns Code, Description, and Length of time in ms between the start and end actions
-- If no start or end action is found then TimeInMS will be -1
-- Description is taken from the Start Action
AS
 
	SET NOCOUNT ON
	SET XACT_ABORT ON  
	 
	DECLARE @StartTime AS DATETIME
	DECLARE @EndTime AS DATETIME
	DECLARE @Length AS INT
	SET @Length = 0
	 
	SELECT @StartTime = ActionTime
	FROM Timings
	WHERE Code = @Code
	AND IsComplete = 0
	 
	SELECT @EndTime = ActionTime
	FROM Timings
	WHERE Code = @Code
	AND IsComplete = 1
	 
	IF ISNULL(CAST(@StartTime AS VARCHAR(12)),'NULL') = 'NULL'
		SET @Length = -1
	 
	IF ISNULL(CAST(@EndTime AS VARCHAR(12)),'NULL') = 'NULL'
		SET @Length = -1
	 
	IF @Length >= 0
		SET @Length = DATEDIFF(ms,@StartTime,@EndTime)
	 
	SELECT Code, Description, @Length AS TimeInMS
	FROM [dbo].[Timings]
	WHERE [Code] = @Code
	AND IsComplete = 0
	 
GO