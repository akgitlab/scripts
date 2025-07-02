# Скрипт автоматической отправки запросов контрагентам

# Определение базового пути
$BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Параметры для отправки email
$SMTPServer = "10.0.85.7"  # Адрес SMTP сервера
$SMTPPort = 25  # Порт SMTP сервера (на Exchange создан отдельный коннектор)
$Subject = "Запрос по подтверждению задолженности"  # Тема письма

# Формирование имени лог-файла
$currentDate = Get-Date -Format "yyyyMMdd"
$LogFilePath = Join-Path $BasePath "log\sendmail_$currentDate.log"

# Относительные пути до шаблонов
$ExcelFilePath = Join-Path $BasePath "templates\indata.xlsx"  # Путь к файлу Excel
$WordTemplatePath = Join-Path $BasePath "templates\attachment.docx" # Путь к шаблону Word

# Параметры для замены значений переменных
$SheetName = "Data"  # Имя листа в Excel
$EmailColumn = 6  # Номер столбца с email адресом контрагента
$ValueColumn1 = 2  # Номер столбца с названием контрагента
$ValueColumn2 = 8  # Номер столбца с ФИО гендиректора
$ValueColumn3 = 4  # Номер столбца с видом задолженности
$ValueColumn4 = 5  # Номер столбца с суммой задолженности

# Параметры для извлечения значений из конкретных ячеек
$SpecificRow1 = 3  # Номер строки для первой ячейки
$SpecificColumn1 = 3  # Номер столбца для первой ячейки
$SpecificRow2 = 3  # Номер строки для второй ячейки
$SpecificColumn2 = 5  # Номер столбца для второй ячейки
$SpecificRow3 = 3  # Номер строки для третьей ячейки
$SpecificColumn3 = 4  # Номер столбца для третьей ячейки
$SpecificRow4 = 3  # Номер строки для четвертой ячейки
$SpecificColumn4 = 2  # Номер столбца для четвертой ячейки

# Приветствие в консоль и лог
$startMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Запуск скрипта отправки запросов контрагентам"
Write-Host $startMessage
Add-Content -Path $LogFilePath -Value $startMessage

# Функция вычисления рабочих дней
function Add-WorkingDays {
    param (
        [DateTime]$StartDate,
        [int]$DaysToAdd
    )

    $currentDate = $StartDate
    $addedDays = 0

    while ($addedDays -lt $DaysToAdd) {
        $currentDate = $currentDate.AddDays(1)

        # Проверка, является ли день рабочим (не выходные)
        if ($currentDate.DayOfWeek -ne [System.DayOfWeek]::Saturday -and $currentDate.DayOfWeek -ne [System.DayOfWeek]::Sunday) {
            $addedDays++
        }
    }

    return $currentDate
}

# Получение текущей даты в нужном формате
$currentDateFormatted = Get-Date -Format "dd MMMM yyyy 'г.'"
$dateFolder = Get-Date -Format "yyyyMMdd"  # Формат для имени папки

# Получение даты через три рабочих дня
$FutureDate = Add-WorkingDays -StartDate (Get-Date) -DaysToAdd 3
$FutureDateFormatted = $FutureDate.ToString("dd MMMM yyyy 'г.'")

# Формирование пути к папке для сохранения документов
$OutputDirectory = Join-Path $BasePath "outgoing\$dateFolder"

# Проверка существования папки для сохранения документов
if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

# Загрузка COM-объекта Excel
$Excel = New-Object -ComObject Excel.Application
$Excel.Visible = $false

# Открытие файла Excel
$Workbook = $Excel.Workbooks.Open($ExcelFilePath)
$Worksheet = $Workbook.Worksheets.Item($SheetName)

# Получение данных с листа Var (скрытый)
$VarSheet = $Workbook.Worksheets.Item("Var")
$VarC2 = $VarSheet.Cells.Item(2, 3).Text  # Ячейка C2
$VarC3 = $VarSheet.Cells.Item(3, 3).Text  # Ячейка C3
$VarD2 = $VarSheet.Cells.Item(2, 4).Text  # Ячейка D2
$VarD3 = $VarSheet.Cells.Item(3, 4).Text  # Ячейка D3

# Получение значений из конкретных ячеек
$SpecificCellValue1 = $Worksheet.Cells.Item($SpecificRow1, $SpecificColumn1).Text
$SpecificCellValue2 = $Worksheet.Cells.Item($SpecificRow2, $SpecificColumn2).Text
$SpecificCellValue3 = $Worksheet.Cells.Item($SpecificRow3, $SpecificColumn3).Text.ToLower()
$SpecificCellValue4 = $Worksheet.Cells.Item($SpecificRow4, $SpecificColumn4).Text

# Функция для замены текста в Word
function Replace-WordText {
    param (
        [Parameter(Mandatory=$true)]
        [Object]$Document,
        [Parameter(Mandatory=$true)]
        [String]$FindText,
        [Parameter(Mandatory=$true)]
        [String]$ReplaceWith
    )
    $Find = $Document.Content.Find
    $Find.Execute($FindText, $false, $false, $false, $false, $false, $true, 1, $false, $ReplaceWith, 2) | Out-Null
}

# Функция для отправки письма со вложенным документом
function Send-Email {
    param (
        [string]$ToEmail,
        [string]$AttachmentPath,
        [string]$FileName,
        [string]$EmailFrom
    )

    $mailMessage = New-Object System.Net.Mail.MailMessage
    $mailMessage.From = $EmailFrom
    $mailMessage.To.Add($ToEmail)
    $mailMessage.Subject = $Subject
	$Value2Trimmed = $Value2 -replace '^\S+\s*', ''  # Удаляем фамилию слово из переменной
    $htmlBody = @"
	<html>
		<body>
			<p>Добрый день, $Value2Trimmed!</p>
			<p>Просим направить письменное подтверждение задолженности.<br>Информация во вложении.</p>
			<p>С уважением,<br>$SpecificCellValue4</p>
		</body>
	</html>
"@
    $mailMessage.Body = $htmlBody
    $mailMessage.IsBodyHtml = $true
    $mailMessage.Attachments.Add($AttachmentPath)

    $smtpClient = New-Object System.Net.Mail.SmtpClient($SMTPServer, $SMTPPort)
    $smtpClient.EnableSsl = $false  # Включаем SSL, если требуется

    try {
        $smtpClient.Send($mailMessage)
        $successMessage = "Сообщение со вложенным файлом успешно отправлено на $ToEmail"
        Write-Host $successMessage
        Add-Content -Path $LogFilePath -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $successMessage"
    }
    catch {
        $errorMessage = "Ошибка при отправке сообщения: $($_.Exception.Message)"
        Write-Host $errorMessage
        Add-Content -Path $LogFilePath -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $errorMessage"
    }
}

# Определение строки в Exel для начала парсинга данных
$row = 7
# Цикл по строкам, пока есть данные в столбце с email
while ($true) {
    # Получение данных из ячейки
    $EmailAddress = $Worksheet.Cells.Item($row, $EmailColumn).Text

    # Проверка на пустое значение и выход из цикла
    if ([string]::IsNullOrWhiteSpace($EmailAddress)) {
        break
    }

    # Вывод email контрагента в консоль
    Write-Host "Обрабатываем email: $EmailAddress"

    # Получение значений из других столбцов
    $Value1 = $Worksheet.Cells.Item($row, $ValueColumn1).Text
    $Value2 = $Worksheet.Cells.Item($row, $ValueColumn2).Text
    $Value3 = $Worksheet.Cells.Item($row, $ValueColumn3).Text
    $Value4 = $Worksheet.Cells.Item($row, $ValueColumn4).Text
	$Value4 = $Worksheet.Cells.Item($row, $ValueColumn4).Text
	if ($Value4.Length -ge 2) {
    $Value4 = $Value4.Substring(0, $Value4.Length - 2).Trim()
	}

    # Замена последних двух символов в $Value3 на "ой"
    if ($Value3.Length -ge 2) {
        $Value3 = $Value3.Substring(0, $Value3.Length - 2) + "ой"
    }

    # Открытие шаблона Word и создание нового документа
    $Word = New-Object -ComObject Word.Application
    #$Document = $Word.Documents.Add($WordTemplatePath)

	$TempTemplatePath = Join-Path $env:TEMP ([IO.Path]::GetFileName($WordTemplatePath))
	Copy-Item -Path $WordTemplatePath -Destination $TempTemplatePath -Force
	$Document = $Word.Documents.Add($TempTemplatePath)

    # Определяем переменные и меняем отправителя в зависимости от организации
	if ($SpecificCellValue4 -like "*ПРАВОВЕСТ*") {
		$INITIALS = $VarC2
		Replace-WordText -Document $Document -FindText "[INITIALS]" -ReplaceWith $INITIALS

		$FromAddress = $VarD2
		$EMAIL_ADDRESS = $VarD2

    # Вставка изображения stamp01.png с масштабом и положением
    $StampPath = Join-Path $BasePath "templates\stamp01.png"
    $inlineShape = $Document.InlineShapes.AddPicture($StampPath)

    # Масштаб 50%
    $inlineShape.ScaleWidth = 32
    $inlineShape.ScaleHeight = 32

    # Преобразование в Shape для позиционирования
    $shape = $inlineShape.ConvertToShape()

    # Константа для расположения за текстом
    $wdWrapBehind = 3
    $shape.WrapFormat.Type = $wdWrapBehind

    # Позиционирование слева сверху (значения в пунктах)
    $shape.Left = 130
    $shape.Top = 305
}
	elseif ($SpecificCellValue4 -like "*Финансовый*") {
		$INITIALS = $VarC3
		Replace-WordText -Document $Document -FindText "[INITIALS]" -ReplaceWith $INITIALS

		$FromAddress = $VarD3
		$EMAIL_ADDRESS = $VarD3

    # Вставка изображения stamp02.png с масштабом и положением
    $StampPath = Join-Path $BasePath "templates\stamp02.png"
    $inlineShape = $Document.InlineShapes.AddPicture($StampPath)

    # Масштаб 50%
    $inlineShape.ScaleWidth = 32
    $inlineShape.ScaleHeight = 32

    # Преобразование в Shape для позиционирования
    $shape = $inlineShape.ConvertToShape()

    # Константа для расположения за текстом
    $wdWrapBehind = 3
    $shape.WrapFormat.Type = $wdWrapBehind

    # Позиционирование слева сверху (значения в пунктах)
    $shape.Left = 130
    $shape.Top = 305
}
	else {
		Replace-WordText -Document $Document -FindText "[INITIALS]" -ReplaceWith ""

		$EMAIL_ADDRESS = $FromAddress
}

    # Проверка, что адрес отправителя определился корректно
    if (-not $FromAddress) {
        $errorMessage = "Ошибка: не задан адрес отправителя."
        Write-Host $errorMessage
        Add-Content -Path $LogFilePath -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $errorMessage"
        exit
}    
	# Вставляем адрес для ответа в документ Word
    Replace-WordText -Document $Document -FindText "[EMAIL_ADDRESS]" -ReplaceWith $EMAIL_ADDRESS

    # Замена текста в формируемом документе
    try {
        Replace-WordText -Document $Document -FindText "[DATE]" -ReplaceWith $currentDateFormatted  # Вставка текущей даты
        Replace-WordText -Document $Document -FindText "[FUTURE_DATE]" -ReplaceWith $FutureDateFormatted  # Вставка даты через 3 рабочих дня
        Replace-WordText -Document $Document -FindText "[SPECIFIC_VALUE1]" -ReplaceWith $SpecificCellValue1  # Вставка значения из первой ячейки
        Replace-WordText -Document $Document -FindText "[SPECIFIC_VALUE2]" -ReplaceWith $SpecificCellValue2  # Вставка значения из второй ячейки
        Replace-WordText -Document $Document -FindText "[SPECIFIC_VALUE3]" -ReplaceWith $SpecificCellValue3  # Вставка значения из третьей ячейки
        Replace-WordText -Document $Document -FindText "[SPECIFIC_VALUE4]" -ReplaceWith $SpecificCellValue4  # Вставка значения из четвертой ячейки
        Replace-WordText -Document $Document -FindText "[VALUE1]" -ReplaceWith $Value1  # Вставка значений из ячеек по порядку
        Replace-WordText -Document $Document -FindText "[VALUE2]" -ReplaceWith $Value2  # Вставка значений из ячеек по порядку
        Replace-WordText -Document $Document -FindText "[VALUE3]" -ReplaceWith $Value3  # Вставка значений из ячеек по порядку
        Replace-WordText -Document $Document -FindText "[VALUE4]" -ReplaceWith $Value4  # Вставка значений из ячеек по порядку

        # Формирование имени файла
        $currentTime = Get-Date -Format "HHmmss"
        $OutputFileName = Join-Path $OutputDirectory ("attachment_" + $currentTime + ".docx")

        # Сохранение сформированного документа
        $Document.SaveAs([ref] [string]$OutputFileName)
        Write-Host "Документ сохранен как: $OutputFileName"

        # Запись пути к вложенному файлу в лог
        Add-Content -Path $LogFilePath -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - Сформирован файл $OutputFileName для отправки на $EmailAddress"

        # Закрытие сформированного документа
        $Document.Close()



        # Задержка перед отправкой письма
        Start-Sleep -Seconds 1

        # Отправка email с прикрепленным документом
        Send-Email -ToEmail $EmailAddress -AttachmentPath $OutputFileName -FileName ("attachment_" + $currentTime + ".docx") -EmailFrom $FromAddress
    }
    catch {
        $errorMessage = "Ошибка при обработке документа: $($_.Exception.Message)"
        Write-Host $errorMessage
        Add-Content -Path $LogFilePath -Value "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $errorMessage"
    }
    finally {
        # Закрытие приложения Word
        $Word.Quit()
    }

    # Переход к следующей строке
    $row++
}

# Закрытие приложения Excel
$Workbook.Close()
$Excel.Quit()

# Освобождение COM-объектов
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($Worksheet) | Out-Null
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($Workbook) | Out-Null
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($Excel) | Out-Null

# Убрать сборщик мусора (garbage collector)
[gc]::Collect()
[gc]::WaitForPendingFinalizers()

# Удаление временного файла шаблона
Remove-Item -Path $TempTemplatePath -ErrorAction SilentlyContinue
