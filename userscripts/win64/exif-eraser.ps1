
## about_Execution_Policies エラーが出た場合
## 1. powershell 起動
## 2. > Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
## 3. スクリプト実行

Add-Type -AssemblyName System.Drawing

# ------------------------------------------------------------------------
# 設定項目
# ------------------------------------------------------------------------

# このスクリプトが存在するパス
$CurrentPath = (Split-Path $MyInvocation.MyCommand.Path -Parent)

# 元画像のディレクトリ
$SourcePath = (Join-Path -Path $CurrentPath '..\..\images' -Resolve)

# サムネイル書き込み先のディレクトリ
$DestPath = (Join-Path -Path $CurrentPath '..\..\source\images' -Resolve)

# サムネイルにする際に画像を縮小する場合の長辺の長さ。十分に大きくすると縮小されない
$ThumbnailSize = 800

# 処理対象のファイル拡張子（元拡張子、サムネイル拡張子、書き出しフォーマット）
$AllowedExtension = @(
[pscustomobject]@{ Original = 'jpg'; MapTo = 'jpg'; Format = [System.Drawing.Imaging.ImageFormat]::Jpeg }
[pscustomobject]@{ Original = 'jpeg'; MapTo = 'jpg'; Format = [System.Drawing.Imaging.ImageFormat]::Jpeg }
#[pscustomobject]@{ Original = 'png'; MapTo = 'png'; Format = [System.Drawing.Imaging.ImageFormat]::Png }
)

# 撮影日時として使うExif項目
$DateTimeProperties = @(
[pscustomobject]@{ Id = 306; Name = 'PropertyTagDateTime' }
[pscustomobject]@{ Id = 36867; Name = 'PropertyTagExifDTOrig' }
[pscustomobject]@{ Id = 36868; Name = 'PropertyTagExifDTDigitized' }
)

# サムネイルに含めてはいけないExif項目
$NgProperties = @(
[pscustomobject]@{ Id = 0; Name = 'GPSVersionID' }
[pscustomobject]@{ Id = 1; Name = 'GPSLatitudeRef' }
[pscustomobject]@{ Id = 2; Name = 'GPSLatitude' }
[pscustomobject]@{ Id = 3; Name = 'GPSLongitudeRef' }
[pscustomobject]@{ Id = 4; Name = 'GPSLongitude' }
[pscustomobject]@{ Id = 5; Name = 'GPSAltitudeRef' }
[pscustomobject]@{ Id = 6; Name = 'GPSAltitude' }
[pscustomobject]@{ Id = 7; Name = 'GPSTimeStamp' }
[pscustomobject]@{ Id = 8; Name = 'GPSSatellites' }
[pscustomobject]@{ Id = 9; Name = 'GPSStatus' }
[pscustomobject]@{ Id = 10; Name = 'GPSMeasureMode' }
[pscustomobject]@{ Id = 11; Name = 'GPSDOP' }
[pscustomobject]@{ Id = 12; Name = 'GPSSpeedRef' }
[pscustomobject]@{ Id = 13; Name = 'GPSSpeed' }
[pscustomobject]@{ Id = 14; Name = 'GPSTrackRef' }
[pscustomobject]@{ Id = 15; Name = 'GPSTrack' }
[pscustomobject]@{ Id = 16; Name = 'GPSImgDirectionRef' }
[pscustomobject]@{ Id = 17; Name = 'GPSImgDirection' }
[pscustomobject]@{ Id = 18; Name = 'GPSMapDatum' }
[pscustomobject]@{ Id = 19; Name = 'GPSDestLatitudeRef' }
[pscustomobject]@{ Id = 20; Name = 'GPSDestLatitude' }
[pscustomobject]@{ Id = 21; Name = 'GPSDestLongitudeRef' }
[pscustomobject]@{ Id = 22; Name = 'GPSDestLongitude' }
[pscustomobject]@{ Id = 23; Name = 'GPSDestBearingRef' }
[pscustomobject]@{ Id = 24; Name = 'GPSDestBearing' }
[pscustomobject]@{ Id = 25; Name = 'GPSDestDistanceRef' }
[pscustomobject]@{ Id = 26; Name = 'GPSDestDistance' }
[pscustomobject]@{ Id = 27; Name = 'GPSProcessingMethod' }
[pscustomobject]@{ Id = 28; Name = 'GPSAreaInformation' }
[pscustomobject]@{ Id = 29; Name = 'GPSDateStamp' }
[pscustomobject]@{ Id = 30; Name = 'GPSDifferential' }
[pscustomobject]@{ Id = 31; Name = 'GPSHPositioningError' }
)


# ------------------------------------------------------------------------
# 長辺サイズを指定以下にするようにサムネイルを生成します
#
# $Image : [System.Drawing.Graphics]
# $Size : int
# returns : [System.Drawing.Graphics]
# ------------------------------------------------------------------------

function Generate-Thumbnail($Image, $Size)
{
    # アスペクト比の指定から画像の高さ(px)と幅(px)を指定
    $OldWidth = $Image.Width
    $OldHeight = $Image.Height
    $NewWidth = $OldWidth
    $NewHeight = $OldHeight
    if (($OldWidth -gt $Size) -or ($OldHeight -gt $Size))
    {
        if ($OldWidth -ge $OldHeight)
        {
            $NewWidth = $Size
            $NewHeight = $OldHeight*$Size/$OldWidth
        }
        else
        {
            $NewWidth = $OldWidth*$Size/$OldHeight
            $NewHeight = $Size
        }
    }

    $Thumbnail = New-Object System.Drawing.Bitmap($Image, $NewWidth, $NewHeight)
    $Graphics = [System.Drawing.Graphics]::FromImage($Thumbnail)
    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::High
    $Graphics.DrawImage($Image, (New-Object System.Drawing.Rectangle(0, 0, $Thumbnail.Width, $Thumbnail.Height)))
    $Graphics.dispose()
    return $Thumbnail
}

# ------------------------------------------------------------------------
# イメージ間でExifを移し替えます
#
# $Image : [System.Drawing.Graphics]
# $Thumbnail : [System.Drawing.Graphics]
# ------------------------------------------------------------------------
function Copy-Filtered-Exif($Image, $Thumbnail)
{
    $PropertyLength = $Image.PropertyItems.Length
    for ($i = 0; $i -lt $PropertyLength; $i++){
        $PropertyItem = $Image.PropertyItems[$i]
        $Id = $PropertyItem.Id
        $MatchedItem = $NgProperties | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
        if ($MatchedItem -ne $null)
        {
            $PropertyName = $MatchedItem.Name
            echo "[app]    detect '$PropertyName($Id)'. skipped."
        }
        else
        {
            $Thumbnail.SetPropertyItem($PropertyItem)
        }
    }
    return
}

# ------------------------------------------------------------------------
# 撮影日時を取得します
#
# $Image : [System.Drawing.Graphics]
# ------------------------------------------------------------------------

function Get-Created-Datetime($Image)
{
    $PropertyLength = $Image.PropertyItems.Length
    $CreatedDatetime = $null
    for ($i = 0; $i -lt $PropertyLength; $i++){
        $PropertyItem = $Image.PropertyItems[$i]
        $Id = $PropertyItem.Id
        $MatchedItem = $DateTimeProperties | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
        if ($MatchedItem -ne $null)
        {
            $RawArray = $PropertyItem.Value
            $RawArray[4] = 47
            $RawArray[7] = 47
            $CreatedDatetime = [System.Text.Encoding]::ASCII.GetString($RawArray)
            break
        }
    }
    if ($CreatedDatetime -eq $null)
    {
        return $null
    }
    return [DateTime]$CreatedDatetime
}


# ------------------------------------------------------------------------
# 画像を1つずつ処理する
#
# $SourceFile : [String] サムネイル生成元ファイルのパス（要存在/相対パスでも良い）
# $DestPath : [String] サムネイル生成先ディレクトリのパス（要存在/相対パスでも良い）
# ------------------------------------------------------------------------

function Process-Once($SourceFile, $DestPath)
{
    echo "[app] checking..."
    # 拡張子チェック
    $SourceFileName = Split-Path $SourceFile -Leaf
    $SourceFileExt = ($SourceFileName -split "\.")[1]
    $SourceFileType = $AllowedExtension| Where-Object { $_.Original -eq $SourceFileExt } | Select-Object -First 1
    $IsValidExt = $SourceFileType -ne $null
    if (-not($IsValidExt))
    {
        echo "[err] invalid file extension."
        return
    }
    # 元画像*ファイル*のフルパス
    $SourceFullPath = Convert-Path $SourceFile -ErrorAction SilentlyContinue

    if ($SourceFullPath -eq $null)
    {
        echo "[err] cannot convert to source file path."
        return
    }
    if (-not( Test-Path $SourceFullPath))
    {
        echo "[err] not found $SourceFullPath"
        return
    }

    # サムネイル生成先の*ディレクトリの*フルパス
    $DestFullPath = Convert-Path $DestPath -ErrorAction SilentlyContinue

    if ($DestFullPath -eq $null)
    {
        echo "[err] cannot convert to thumnbnil dir path."
        return
    }
    if (-not( Test-Path $DestFullPath))
    {
        echo "[err] not found $DestFullPath"
        return
    }



    echo "[app] loading $SourceFileName ..."
    $Image = New-Object System.Drawing.Bitmap($SourceFullPath)

    echo "[app] generating thumbnail..."
    $Thumbnail = Generate-Thumbnail $Image $ThumbnailSize

    echo "[app] exif processing..."
    Copy-Filtered-Exif $Image $Thumbnail

    # 保存先決定
    # ファイル名に使う日時をExifから取得するが、それが不可能であればファイルの生成日時を使う
    echo "[app] prepare to save file..."
    $FileCreatedAt = (Get-ItemProperty $SourceFullPath).CreationTime
    $ExifCreatedAt = Get-Created-Datetime $Image
    if ($ExifCreatedAt -ne $null)
    {
        $FileCreatedAt = $ExifCreatedAt
    }
    $DestFileName = $FileCreatedAt.ToString("yyyyMMddTHHmmss") + "." + ($SourceFileType.MapTo)
    $DestFile = (Join-Path -Path $DestFullPath $DestFileName)

    # 保存
    echo "[app] writing $DestFileName ..."
    $Thumbnail.Save($DestFile, $SourceFileType.Format)

    echo "[app] clean up"
    $Thumbnail.Dispose()
    $Image.Dispose()
}


# 主処理

if ($SourcePath -eq $null)
{
    echo "[err] not found $SourcePath"
    return
}
if ($DestPath -eq $null)
{
    echo "[err] not found $DestPath"
    return
}

$Files = Get-ChildItem $SourcePath\*.* -Recurse -File
$Files | % {
    $SourceFile = (Join-Path -Path $SourcePath $_.Name)
    echo $SourceFile
    Process-Once $SourceFile $DestPath
}

