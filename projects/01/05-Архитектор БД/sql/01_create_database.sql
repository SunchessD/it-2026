-- ============================================================
-- ModelLab — Создание структуры базы данных
-- Microsoft Access
-- ============================================================

-- ============================================================
-- МОДУЛЬ "ПОЛЬЗОВАТЕЛИ И АВТОРИЗАЦИЯ"
-- ============================================================

CREATE TABLE Пользователь (
     IdПользователя AUTOINCREMENT PRIMARY KEY,
     Имя TEXT(100) NOT NULL,
     Email TEXT(150) NOT NULL,
     ХешПароля TEXT(255) NOT NULL,
     СтатусАктивации TEXT(20) NOT NULL DEFAULT "Неактивна",
     РольПлатформы TEXT(30) NOT NULL DEFAULT "пользователь",
     ПризнакБлокировки YESNO DEFAULT False,
     ДатаРегистрации DATETIME DEFAULT Now()
 );

-- ============================================================
-- МОДУЛЬ "МОДЕЛИ И СОВМЕСТНАЯ РАБОТА"
-- ============================================================

-- Модель
 CREATE TABLE Модель (
     IdМодели AUTOINCREMENT PRIMARY KEY,
     IdВладельца LONG NOT NULL,
     Название TEXT(200) NOT NULL,
     Описание MEMO,
     ДатаСоздания DATETIME DEFAULT Now(),
     ДатаИзменения DATETIME DEFAULT Now(),
     ТипДоступа TEXT(30) DEFAULT "приватная"
 );

-- ДоступКМодели
 CREATE TABLE ДоступКМодели (
     IdДоступа AUTOINCREMENT PRIMARY KEY,
     IdПользователя LONG NOT NULL,
     IdМодели LONG NOT NULL,
     УровеньДоступа TEXT(30) NOT NULL,
     ДатаПредоставления DATETIME DEFAULT Now()
 );

-- СостояниеМодели
 CREATE TABLE СостояниеМодели (
     IdСостояния AUTOINCREMENT PRIMARY KEY,
     IdМодели LONG NOT NULL,
     ДатаСоздания DATETIME DEFAULT Now(),
     ЯвляетсяТекущим YESNO DEFAULT False
 );

-- ВерсияМодели
 CREATE TABLE ВерсияМодели (
     IdВерсии AUTOINCREMENT PRIMARY KEY,
     IdМодели LONG NOT NULL,
     IdСостояния LONG NOT NULL,
     Название TEXT(150),
     ДатаФиксации DATETIME DEFAULT Now(),
     ПризнакНеизменяемости YESNO DEFAULT True
 );

-- ============================================================
-- МОДУЛЬ "СТРУКТУРА МОДЕЛИ"
-- ============================================================

-- ЭлементМодели
 CREATE TABLE ЭлементМодели (
     IdЭлемента AUTOINCREMENT PRIMARY KEY,
     IdСостояния LONG NOT NULL,
     Название TEXT(150) NOT NULL,
     ТипЭлемента TEXT(30) NOT NULL,
     ПозицияX LONG DEFAULT 0,
     ПозицияY LONG DEFAULT 0
 );

-- Связь
 CREATE TABLE Связь (
     IdСвязи AUTOINCREMENT PRIMARY KEY,
     IdЭлементаИсточника LONG NOT NULL,
     IdЭлементаЦели LONG NOT NULL,
     ТипВзаимодействия TEXT(50),
     IdСостояния LONG NOT NULL
 );

-- Параметр
 CREATE TABLE Параметр (
     IdПараметра AUTOINCREMENT PRIMARY KEY,
     IdСостояния LONG NOT NULL,
     Название TEXT(100) NOT NULL,
     ТипЗначения TEXT(30),
     Значение TEXT(255),
     ИзменяемостьПриЗапуске YESNO DEFAULT False
 );

-- ПрограммнаяЛогика
 CREATE TABLE ПрограммнаяЛогика (
     IdЛогики AUTOINCREMENT PRIMARY KEY,
     IdСостояния LONG NOT NULL,
     ТекстPython MEMO,
     ДатаИзменения DATETIME DEFAULT Now()
 );

-- ============================================================
-- МОДУЛЬ "СИМУЛЯЦИЯ"
-- ============================================================

-- РезультатСимуляции
 CREATE TABLE РезультатСимуляции (
     IdРезультата AUTOINCREMENT PRIMARY KEY,
     IdМодели LONG NOT NULL,
     IdВерсии LONG,
     ПараметрыЗапуска MEMO,
     ДатаЗапуска DATETIME DEFAULT Now(),
     Статус TEXT(30) DEFAULT "выполняется",
     ДанныеРезультата MEMO
 );
