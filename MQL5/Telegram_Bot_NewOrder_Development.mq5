//+------------------------------------------------------------------+
//|                                              Telegram_Bot_EA.mq5 |
//|                        Copyright 2014, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2014, MetaQuotes Software Corp."
#property link      "http://www.mql5.com"
#property version   "1.00"
#property strict

#include <stderror.mqh>
#include <stdlib.mqh>
#include <Comment.mqh>
#include <Telegram.mqh>
#include <json.mqh>
#include <hash.mqh>
#include <ErrorDescription.mqh>

const ENUM_TIMEFRAMES _periods[]= {PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H4,PERIOD_D1,PERIOD_W1,PERIOD_MN1};
//+------------------------------------------------------------------+
//|   CMyBot                                                         |
//+------------------------------------------------------------------+
class CMyBot: public CCustomBot
  {
private:
   ENUM_LANGUAGES    m_lang;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_period;
   string            m_template;
   CArrayString      m_templates;

public:
   //+------------------------------------------------------------------+
   void              Language(const ENUM_LANGUAGES _lang) {m_lang=_lang;}

   //+------------------------------------------------------------------+
   int               Templates(const string _list)
     {
      m_templates.Clear();
      //--- parsing
      string text=StringTrim(_list);
      if(text=="")
         return(0);

      //---
      while(StringReplace(text,"  "," ")>0);
      StringReplace(text,";"," ");
      StringReplace(text,","," ");

      //---
      string array[];
      int amount=StringSplit(text,' ',array);
      amount=fmin(amount,5);

      for(int i=0; i<amount; i++)
        {
         array[i]=StringTrim(array[i]);
         if(array[i]!="")
            m_templates.Add(array[i]);
        }

      return(amount);
     }

   //+------------------------------------------------------------------+
   int               SendScreenShot(const long _chat_id,
                                    const string _symbol,
                                    const ENUM_TIMEFRAMES _period,
                                    const string _template=NULL)
     {
      int result=0;

      long chart_id=ChartOpen(_symbol,_period);
      if(chart_id==0)
         return(ERR_CHART_NOT_FOUND);

      ChartSetInteger(ChartID(),CHART_BRING_TO_TOP,true);

      //--- updates chart
      int wait=60;
      while(--wait>0)
        {
         if(SeriesInfoInteger(_symbol,_period,SERIES_SYNCHRONIZED))
            break;
         Sleep(50);
        }

      if(_template!=NULL)
         if(!ChartApplyTemplate(chart_id,_template))
            PrintError(_LastError,InpLanguage);

      ChartRedraw(chart_id);
      Sleep(50);

      ChartSetInteger(chart_id,CHART_SHOW_GRID,false);
      ChartSetInteger(chart_id,CHART_SHIFT,true);
      ChartSetInteger(chart_id,CHART_SHOW_PERIOD_SEP,false);
      MqlDateTime tm;
      TimeToStruct(TimeCurrent(),tm);
      string timeBeauty = IntegerToString(tm.year)
                          + "_" + IntegerToString(tm.mon)
                          +  "_" + IntegerToString(tm.day)+"__"+IntegerToString(tm.hour)
                          + "_"+IntegerToString(tm.min)+ "_"+IntegerToString(tm.sec);
      string filename=StringFormat("%s%d.gif",_symbol,_period);
      Comment(filename);
      Print(filename);
      if(FileIsExist(filename))
         FileDelete(filename);
      ChartRedraw(chart_id);

      Sleep(50);

      bool resultShot = ChartScreenShot(chart_id,filename,2560,1200,ALIGN_RIGHT);
      ChartClose(chart_id);
      if(resultShot)
        {
         Sleep(500);

         bot.SendChatAction(_chat_id,ACTION_UPLOAD_PHOTO);

         //--- waitng 2 minutes for save screenshot
         //wait=4800;
         //while(!FileIsExist(filename) && --wait>0)
         //   Sleep(50);

         //---
         if(FileIsExist(filename))
           {
            string screen_id;
            result=bot.SendPhoto(photo_id,_chat_id,filename,_symbol+"_"+StringSubstr(EnumToString(_period),7));
           }
         else
           {
            string mask=m_lang==LANGUAGE_EN?"Screenshot file '%s' not created.":"Файл скриншота '%s' не создан.";
            PrintFormat(mask,filename);
           }
        }
      return(result);
     }

   //+------------------------------------------------------------------+
   void              ProcessMessages(void)
     {

#define EMOJI_TOP    "\xF51D"
#define EMOJI_BACK   "\xF519"
#define KEYB_MENU    "[[\"MENU\"]]"
#define KEYB_MAIN    (m_lang==LANGUAGE_EN)?"[[\"New Order\"],[\"Account Info\"],[\"Quotes\"],[\"Charts\"]]":"[[\"Информация\"],[\"Котировки\"],[\"Графики\"]]"
#define KEYB_SYMBOLS "[[\""+EMOJI_TOP+"\",\"GBPUSD\",\"EURUSD\"],[\"AUDUSD\",\"USDJPY\",\"EURJPY\"],[\"USDCAD\",\"USDCHF\",\"EURCHF\"]]"
#define KEYB_PERIODS "[[\""+EMOJI_TOP+"\",\"M1\",\"M5\",\"M15\"],[\""+EMOJI_BACK+"\",\"M30\",\"H1\",\"H4\"],[\" \",\"D1\",\"W1\",\"MN1\"]]"
#define MAGIC_INTRADAY  1560240
#define MAGIC_SWING     24543
#define MAGIC_MANUAL    111411

      for(int i=0; i<m_chats.Total(); i++)
        {
         CCustomChat *chat=m_chats.GetNodeAtIndex(i);
         if(!chat.m_new_one.done)
           {
            chat.m_new_one.done=true;
            string text=chat.m_new_one.message_text;
            StringReplace(text, "#webhook\n", "");
            StringReplace(text, "#webhook", "");
            //--- start
            if(text=="/start" || text=="/help" || text == "MENU")
              {
               chat.m_state=0;
               string msg="The bot works with your trading account:\n";
               msg+="/new_order - create new order\n";
               msg+="/info - get account information\n";
               msg+="/quotes - get quotes\n";
               msg+="/charts - get chart images\n";

               if(m_lang==LANGUAGE_RU)
                 {
                  msg="Бот работает с вашим торговым счетом:\n";
                  msg+="/info - запросить информацию по счету\n";
                  msg+="/quotes - запросить котировки\n";
                  msg+="/charts - запросить график\n";
                 }

               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_MAIN,false,false));
               continue;
              }

            //---
            if(text==EMOJI_TOP)
              {
               chat.m_state=0;
               string msg=(m_lang==LANGUAGE_EN)?"Choose a menu item":"Выберите пункт меню";
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_MENU,false,false));
               continue;
              }

            //---
            if(text==EMOJI_BACK)
              {
               if(chat.m_state==31)
                 {
                  chat.m_state=3;
                  string msg=(m_lang==LANGUAGE_EN)?"Enter a symbol name like 'EURUSD'":"Введите название инструмента, например 'EURUSD'";
                  SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_SYMBOLS,false,false));
                 }
               else
                  if(chat.m_state==32)
                    {
                     chat.m_state=31;
                     string msg=(m_lang==LANGUAGE_EN)?"Select a timeframe like 'H1'":"Введите период графика, например 'H1'";
                     SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_PERIODS,false,false));
                    }
                  else
                    {
                     chat.m_state=-1;
                     string msg=(m_lang==LANGUAGE_EN)?"Choose a menu item":"Выберите пункт меню";
                     SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_MAIN,false,false));
                    }
               continue;
              }

            //---
            if(text=="/info" || text=="Account Info" || text=="Информация")
              {
               chat.m_state=1;
               string currency=AccountInfoString(ACCOUNT_CURRENCY);
               string msg=StringFormat("%d: %s\n",AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER));
               msg+=StringFormat("%s: %.2f %s\n",(m_lang==LANGUAGE_EN)?"Balance":"Баланс",AccountInfoDouble(ACCOUNT_BALANCE),currency);
               msg+=StringFormat("%s: %.2f %s\n",(m_lang==LANGUAGE_EN)?"Profit":"Прибыль",AccountInfoDouble(ACCOUNT_PROFIT),currency);
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_MAIN,false,false));
              }

            //---
            if(text=="/quotes" || text=="Quotes" || text=="Котировки")
              {
               chat.m_state=2;
               string msg=(m_lang==LANGUAGE_EN)?"Enter a symbol name like EURUSD":"Введите название инструмента, например 'EURUSD'";
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_SYMBOLS,false,false));
               continue;
              }

            //---
            if(text=="/charts" || text=="Charts" || text=="Графики")
              {
               chat.m_state=3;
               string msg=(m_lang==LANGUAGE_EN)?"Enter a symbol name like EURUSD":"Введите название инструмента, например 'EURUSD'";
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_SYMBOLS,false,false));
               continue;
              }
            //---
            if(text=="/new_order" || text == "New Order")
              {
               chat.m_state=4; //Tao order
               string msg=(m_lang==LANGUAGE_EN)?"Enter Json Format of Order":"Missing";
               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_MENU,false,false));
               continue;
              }
            if (StringFind(text, "/new_order|") >= 0) { //Receive order from python server
               StringReplace(text, "/new_order|", "");
               chat.m_state=4;
               Print(text);
            }
            if (StringFind(text, "/close_order|") >= 0) { //Receive order from python server
               StringReplace(text, "/close_order|", "");
               chat.m_state=5;
               Print(text);
            }
            if (StringFind(text, "/market_order|") >= 0) { //Receive order from python server
               StringReplace(text, "/market_order|", "");
               chat.m_state=6;
               Print(text);
            }
            //--- Quotes
            if (chat.m_state == 4) {
               string result = MessageReceive(text, "open");
               SendMessage(chat.m_id,result,ReplyKeyboardMarkup(KEYB_MENU,false,false));
               continue;
            }
            if (chat.m_state == 5) {
               string result = MessageReceive(text, "close");
               SendMessage(chat.m_id,result,ReplyKeyboardMarkup(KEYB_MENU,false,false));
               continue;
            }
            if (chat.m_state == 6) {
               string result = MessageReceive(text, "market");
               SendMessage(chat.m_id,result,ReplyKeyboardMarkup(KEYB_MENU,false,false));
               continue;
            }
            if(chat.m_state==2)
              {
               string mask=(m_lang==LANGUAGE_EN)?"Invalid symbol name '%s'":"Инструмент '%s' не найден";
               string msg=StringFormat(mask,text);
               StringToUpper(text);
               string symbol=text;
               if(SymbolSelect(symbol,true))
                 {
                  double open[1]= {0};

                  m_symbol=symbol;
                  //--- upload history
                  for(int k=0; k<3; k++)
                    {
#ifdef __MQL4__
                     double array[][6];
                     ArrayCopyRates(array,symbol,PERIOD_D1);
#endif

                     Sleep(2000);
                     CopyOpen(symbol,PERIOD_D1,0,1,open);
                     if(open[0]>0.0)
                        break;
                    }

                  int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
                  double bid=SymbolInfoDouble(symbol,SYMBOL_BID);

                  CopyOpen(symbol,PERIOD_D1,0,1,open);
                  if(open[0]>0.0)
                    {
                     double percent=100*(bid-open[0])/open[0];
                     //--- sign
                     string sign=ShortToString(0x25B2);
                     if(percent<0.0)
                        sign=ShortToString(0x25BC);

                     msg=StringFormat("%s: %s %s (%s%%)",symbol,DoubleToString(bid,digits),sign,DoubleToString(percent,2));
                    }
                  else
                    {
                     msg=(m_lang==LANGUAGE_EN)?"No history for ":"Нет истории для "+symbol;
                    }
                 }

               SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_SYMBOLS,false,false));
               continue;
              }

            //--- Charts
            if(chat.m_state==3)
              {

               StringToUpper(text);
               string symbol=text;
               if(SymbolSelect(symbol,true))
                 {
                  m_symbol=symbol;

                  chat.m_state=31;
                  string msg=(m_lang==LANGUAGE_EN)?"Select a timeframe like 'H1'":"Введите период графика, например 'H1'";
                  SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_PERIODS,false,false));
                 }
               else
                 {
                  string mask=(m_lang==LANGUAGE_EN)?"Invalid symbol name '%s'":"Инструмент '%s' не найден";
                  string msg=StringFormat(mask,text);
                  SendMessage(chat.m_id,msg,ReplyKeyboardMarkup(KEYB_SYMBOLS,false,false));
                 }
               continue;
              }

            //Charts->Periods
            if(chat.m_state==31)
              {
               bool found=false;
               int total=ArraySize(_periods);
               for(int k=0; k<total; k++)
                 {
                  string str_tf=StringSubstr(EnumToString(_periods[k]),7);
                  if(StringCompare(str_tf,text,false)==0)
                    {
                     m_period=_periods[k];
                     found=true;
                     break;
                    }
                 }

               if(found)
                 {
                  //--- template
                  chat.m_state=32;
                  string str="[[\""+EMOJI_BACK+"\",\""+EMOJI_TOP+"\"]";
                  str+=",[\"None\"]";
                  for(int k=0; k<m_templates.Total(); k++)
                     str+=",[\""+m_templates.At(k)+"\"]";
                  str+="]";

                  SendMessage(chat.m_id,(m_lang==LANGUAGE_EN)?"Select a template":"Выберите шаблон",ReplyKeyboardMarkup(str,false,false));
                 }
               else
                 {
                  SendMessage(chat.m_id,(m_lang==LANGUAGE_EN)?"Invalid timeframe":"Неправильно задан период графика",ReplyKeyboardMarkup(KEYB_PERIODS,false,false));
                 }
               continue;
              }
            //---
            if(chat.m_state==32)
              {
               m_template=text;
               if(m_template=="None")
                  m_template=NULL;
               int result=SendScreenShot(chat.m_id,m_symbol,m_period,m_template);
               if(result!=0)
                  Print(GetErrorDescription(result,InpLanguage));
              }
           }
        }
     }
  };

//+------------------------------------------------------------------+
#define EXPERT_NAME     "Telegram Bot"
#define EXPERT_VERSION  "1.00"
#property version       EXPERT_VERSION
#define CAPTION_COLOR   clrWhite
#define LOSS_COLOR      clrOrangeRed

//+------------------------------------------------------------------+
//|   Input parameters                                               |
//+------------------------------------------------------------------+
input ENUM_LANGUAGES    InpLanguage=LANGUAGE_EN;//Language
input ENUM_UPDATE_MODE  InpUpdateMode=UPDATE_NORMAL;//Update Mode
//input string            InpToken="1037718376:AAGCaiUwO8682dDdSEYxcKl0SQegTQMr3Cg"; //Trading Bot Telegram Token -> Live
input string            InpToken="936355269:AAFQHsmEgmZAtqYmRsu_fxTg_BojzGl7uHY"; //Tereki MT4 for -> Development
input string            InpUserNameFilter="";//Whitelist Usernames
input string            InpTemplates="ADX;BollingerBands;Momentum";//Templates

//---
CComment       comment;
CMyBot         bot;
JSONParser *parser = new JSONParser();
ENUM_RUN_MODE  run_mode;
datetime       time_check; 
int            web_error;
int            init_error;
string         photo_id=NULL;
//+------------------------------------------------------------------+
//|   init                                                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   run_mode=GetRunMode();

//--- stop working in tester
   if(run_mode!=RUN_LIVE)
     {
      PrintError(ERR_RUN_LIMITATION,InpLanguage);
      return(INIT_FAILED);
     }

   int y=40;
   if(ChartGetInteger(0,CHART_SHOW_ONE_CLICK))
      y=120;
   comment.Create("myPanel",20,y);
   comment.SetColor(clrDimGray,clrBlack,220);
//--- set language
   bot.Language(InpLanguage);

//--- set token
   init_error=bot.Token(InpToken);

//--- set filter
   bot.UserNameFilter(InpUserNameFilter);

//--- set templates
   bot.Templates(InpTemplates);
//--- init json parser
   InitOrdering();
   //TestJson2();
//--- set timer
   int timer_ms=3000;
   switch(InpUpdateMode)
     {
      case UPDATE_FAST:
         timer_ms=1000;
         break;
      case UPDATE_NORMAL:
         timer_ms=2000;
         break;
      case UPDATE_SLOW:
         timer_ms=3000;
         break;
      default:
         timer_ms=3000;
         break;
     };
   EventSetMillisecondTimer(timer_ms);
   OnTimer();
//MessageReceive("");
//--- done
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//|   deinit                                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   if(reason==REASON_CLOSE ||
      reason==REASON_PROGRAM ||
      reason==REASON_PARAMETERS ||
      reason==REASON_REMOVE ||
      reason==REASON_RECOMPILE ||
      reason==REASON_ACCOUNT ||
      reason==REASON_INITFAILED)
     {
      time_check=0;
      comment.Destroy();
     }
//--- deinit json parser
   delete parser;
   StopClient();
//---
   EventKillTimer();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
//|   OnChartEvent                                                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   comment.OnChartEvent(id,lparam,dparam,sparam);
  }
//+------------------------------------------------------------------+
//|   OnTimer                                                        |
//+------------------------------------------------------------------+
void OnTimer()
  {

//--- show init error
   if(init_error!=0)
     {
      //--- show error on display
      CustomInfo info;
      GetCustomInfo(info,init_error,InpLanguage);

      //---
      comment.Clear();
      comment.SetText(0,StringFormat("%s v.%s",EXPERT_NAME,EXPERT_VERSION),CAPTION_COLOR);
      comment.SetText(1,info.text1, LOSS_COLOR);
      if(info.text2!="")
         comment.SetText(2,info.text2,LOSS_COLOR);
      comment.Show();

      return;
     }

//--- show web error
   if(run_mode==RUN_LIVE)
     {

      //--- check bot registration
      if(time_check<TimeLocal()-PeriodSeconds(PERIOD_H1))
        {
         time_check=TimeLocal();
         if(TerminalInfoInteger(TERMINAL_CONNECTED))
           {
            //---
            web_error=bot.GetMe();
            if(web_error!=0)
              {
               //---
               if(web_error==ERR_NOT_ACTIVE)
                 {
                  time_check=TimeCurrent()-PeriodSeconds(PERIOD_H1)+300;
                 }
               //---
               else
                 {
                  time_check=TimeCurrent()-PeriodSeconds(PERIOD_H1)+5;
                 }
              }
           }
         else
           {
            web_error=ERR_NOT_CONNECTED;
            time_check=0;
           }
        }

      //--- show error
      if(web_error!=0)
        {
         comment.Clear();
         comment.SetText(0,StringFormat("%s v.%s",EXPERT_NAME,EXPERT_VERSION),CAPTION_COLOR);

         if(
#ifdef __MQL4__ web_error==ERR_FUNCTION_NOT_CONFIRMED #endif
#ifdef __MQL5__ web_error==ERR_FUNCTION_NOT_ALLOWED #endif
         )
           {
            time_check=0;

            CustomInfo info= {0};
            GetCustomInfo(info,web_error,InpLanguage);
            comment.SetText(1,info.text1,LOSS_COLOR);
            comment.SetText(2,info.text2,LOSS_COLOR);
           }
         else
            comment.SetText(1,GetErrorDescription(web_error,InpLanguage),LOSS_COLOR);

         comment.Show();
         return;
        }
     }

//---
   bot.GetUpdates();

//---
   if(run_mode==RUN_LIVE)
     {
      comment.Clear();
      comment.SetText(0,StringFormat("%s v.%s",EXPERT_NAME,EXPERT_VERSION),CAPTION_COLOR);
      comment.SetText(1,StringFormat("%s: %s",(InpLanguage==LANGUAGE_EN)?"Bot Name":"Имя Бота",bot.Name()),CAPTION_COLOR);
      comment.SetText(2,StringFormat("%s: %d",(InpLanguage==LANGUAGE_EN)?"Chats":"Чаты",bot.ChatsTotal()),CAPTION_COLOR);
      comment.Show();
     }

//---
   bot.ProcessMessages();
  }
//+------------------------------------------------------------------+
//|   GetCustomInfo                                                  |
//+------------------------------------------------------------------+
void GetCustomInfo(CustomInfo &info,
                   const int _error_code,
                   const ENUM_LANGUAGES _lang)
  {
//--- функция для сообещний пользователей
   switch(_error_code)
     {
#ifdef __MQL5__
      case ERR_FUNCTION_NOT_ALLOWED:
         info.text1 = (_lang==LANGUAGE_EN)?"The URL does not allowed for WebRequest":"Этого URL нет в списке для WebRequest.";
         info.text2 = TELEGRAM_BASE_URL;
         break;
#endif
#ifdef __MQL4__
      case ERR_FUNCTION_NOT_CONFIRMED:
         info.text1 = (_lang==LANGUAGE_EN)?"The URL does not allowed for WebRequest":"Этого URL нет в списке для WebRequest.";
         info.text2 = TELEGRAM_BASE_URL;
         break;
#endif

      case ERR_TOKEN_ISEMPTY:
         info.text1 = (_lang==LANGUAGE_EN)?"The 'Token' parameter is empty.":"Параметр 'Token' пуст.";
         info.text2 = (_lang==LANGUAGE_EN)?"Please fill this parameter.":"Пожалуйста задайте значение для этого параметра.";
         break;
     }

  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//--- Declaration of constants
#define OP_BUY 0           //Buy 
#define OP_SELL 1          //Sell 
#define OP_BUYLIMIT 2      //Pending order of BUY LIMIT type 
#define OP_SELLLIMIT 3     //Pending order of SELL LIMIT type 
#define OP_BUYSTOP 4       //Pending order of BUY STOP type 
#define OP_SELLSTOP 5      //Pending order of SELL STOP type 
//--- Inputs
input string OrderSegment            = "----------------------------";
input bool   IsMiniPipBroker         = false;
input double MinLots                 = 0.0;                    // Limit the minimum lots (Default is 0.00)
input double MaxLots                 = 0.0;                    // Limit the maximum lots (Default is 0.00)
input double PercentLots             = 100;                     // Lots Percent from Signal (Default is 100)
input int    Slippage                = 5;
input bool   AllowOpenTrade          = true;                    // Allow Open a New Order (Default is true)
input bool   AllowCloseTrade         = true;                    // Allow Close a Order (Default is true)
input bool   AllowModifyTrade        = true;                    // Allow Modify a Order (Default is true)
input string AllowSymbols            = "";                      // Allow Trading Symbols (Ex: EURUSDq,EURUSDx,EURUSDa)
input bool   InvertOrder             = false;                   // Invert original trade direction (Default is false)
input double MinFreeMargin           = 0.00;                    // Minimum Free Margin to Open a New Order (Default is 0.00)
input string SymbolPrefixAdjust      = "";                      // Adjust the Symbol Name as Local Symbol Name (Ex: d=q,d=)

//--- Globales Struct
struct ClosedOrder
  {
   int               s_orderid;
   int               s_before_orderid;
   int               orderid;
  };

struct SymbolPrefix
  {
   string            s_name;
   string            d_name;
  };

//--- Globales Application
const string app_name    = "Telegram Ordering";

//--- Globales Order
double order_minlots     = 0.00;
double order_maxlots     = 0.00;
double order_percentlots = 1;
int    order_slippage    = 0;
bool   order_allowopen   = true;
bool   order_allowclose  = true;
bool   order_allowmodify = true;
bool   order_invert      = false;

//--- Globales Account
int    account_subscriber    = 0;
double account_minmarginfree = 0.00;

//--- Globales File
string       local_drectoryname    = "Data";
string       local_pclosedfilename = "partially_closed.bin";
ClosedOrder       local_pclosed[];

SymbolPrefix      local_symbolprefix[];
string            local_symbolallow[];
int          symbolprefix_size     = 0;
int          symbolallow_size      = 0;

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void InitOrdering()
  {

   
   if(DetectEnvironment() == false)
     {
      Alert("Error: The property is fail, please check and try again.");

      return;
     }
  }

//+------------------------------------------------------------------+
//| Detect the script parameters                                     |
//+------------------------------------------------------------------+
bool              DetectEnvironment()
  {
//if (IsDemo())
//  {
//    Print("Account is Demo, please switch the Demo account to Real account.");
//    return false;
//  }

   if(TerminalInfoInteger(TERMINAL_DLLS_ALLOWED) == false)
     {
      Print("DLL call is not allowed. ", app_name, " cannot run.");
      return false;
     }

   order_minlots = MinLots;
   order_maxlots = MaxLots;
   order_percentlots = (order_percentlots > 0) ? PercentLots : 100;
   order_slippage = Slippage;
   order_allowopen = AllowOpenTrade;
   order_allowclose = AllowCloseTrade;
   order_allowmodify = AllowModifyTrade;
   order_invert = InvertOrder;

   account_minmarginfree = MinFreeMargin;

// Load the Symbol prefix maps
   if(SymbolPrefixAdjust != "")
     {
      string symboldata[];
      int    symbolsize = StringSplit(SymbolPrefixAdjust, ',', symboldata);
      int    symbolindex = 0;

      ArrayResize(local_symbolprefix, symbolsize);

      for(symbolindex=0; symbolindex<symbolsize; symbolindex++)
        {
         string prefixdata[];
         int    prefixsize = StringSplit(symboldata[symbolindex], '=', prefixdata);

         if(prefixsize == 2)
           {
            local_symbolprefix[symbolindex].s_name = prefixdata[0];
            local_symbolprefix[symbolindex].d_name = prefixdata[1];
           }
        }

      symbolprefix_size = symbolsize;
     }

// Load the Symbol allow map
   if(AllowSymbols != "")
     {
      string symboldata[];
      int    symbolsize = StringSplit(AllowSymbols, ',', symboldata);
      int    symbolindex = 0;

      ArrayResize(local_symbolallow, symbolsize);

      for(symbolindex=0; symbolindex<symbolsize; symbolindex++)
        {
         if(symboldata[symbolindex] == "")
            continue;

         local_symbolallow[symbolindex] = symboldata[symbolindex];
        }

      symbolallow_size = symbolsize;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Stop the client                                                  |
//+------------------------------------------------------------------+
void              StopClient()
  {
// Save local closed order to file
   LocalClosedDataToFile();

   ArrayFree(local_pclosed);
   ArrayFree(local_symbolprefix);
   ArrayFree(local_symbolallow);
  }

//+------------------------------------------------------------------+
//| Receive Message                                                  |
//+------------------------------------------------------------------+
string GlobalMessagePlus = "";
string              MessageReceive(string message, string type)
  {
// Load closed order to memory
   LocalClosedDataToMemory();
   GlobalMessagePlus = "";
 // Hard code for test only
   if(type == "open" && message != "" && AccountInfoDouble(ACCOUNT_EQUITY) > 0.00)
     {
         bool checkValid = ParseMessage(message);
         if(checkValid) {
            bool result = ParseOrderFromSingal(message, type);
            if (result) return "ORDER SUCCESSFUL!" + " " + GlobalMessagePlus;
            else {
               int check=GetLastError();
               if(check!=ERR_SUCCESS) return ("ORDER FAILED: " + ErrorDescription(check) + " " + GlobalMessagePlus);
               return "ORDER FAILED: CAN'T DETECT REASON"+ " " + GlobalMessagePlus;
            }
         }
     }
     if(type == "close" && message != "")
     {
         bool checkValid = ParseMessage(message);
         if(checkValid) {
            bool result = ParseOrderFromSingal(message, type);
            if (result) return "ORDER SUCCESSFUL!"+ " " + GlobalMessagePlus;
            else {
               int check=GetLastError();
               if(check!=ERR_SUCCESS) return ("ORDER FAILED: " + ErrorDescription(check)+ " " + GlobalMessagePlus);
               return "ORDER FAILED: CAN'T DETECT REASON"+ " " + GlobalMessagePlus;
            }
         }
     }
     if(type == "market" && message != "" && AccountInfoDouble(ACCOUNT_EQUITY) > 0.00)
     {
         bool checkValid = ParseMessage(message);
         if(checkValid) {
            bool result = ParseOrderFromSingal(message, type);
            if (result) return "ORDER SUCCESSFUL!"+ " " + GlobalMessagePlus;
            else {
               int check=GetLastError();
               if(check!=ERR_SUCCESS) return ("ORDER FAILED: " + ErrorDescription(check)+ " " + GlobalMessagePlus);
               return "ORDER FAILED: CAN'T DETECT REASON"+ " " + GlobalMessagePlus;
            }
         }
     }
     return "WRONG JSON"+ " " + GlobalMessagePlus; 
  }

//+------------------------------------------------------------------+
//| Parse the message from server signal                             |
//+------------------------------------------------------------------+
bool              ParseMessage(const string message)
  {
   if(message == "")
      return false;

   JSONValue *jv = parser.parse(message);

   if(jv == NULL)
     {
      Print("error:"+(string)parser.getErrorCode()+parser.getErrorMessage());
      delete jv;
      return false;
     }
   else
     {
      Print("PARSED:"+jv.toString());
      if(jv.isObject())    // check root value is an object. (it can be an array)
        {
         delete jv;
         return true;
        }
     }
   delete jv;
   return false;
  }

//+------------------------------------------------------------------+
//| Parse the order from signal message                              |
//+------------------------------------------------------------------+
bool IsNull(JSONValue *val) { return val==NULL || val.isNull(); }
bool              ParseOrderFromSingal(const string message, string type)
  {
  JSONValue *jv = parser.parse(message);
  JSONObject*orderdata = jv;
  bool hasSymbol = StringFind(message, "symbol", 0) >= 0 && orderdata.isString("symbol");
  bool hasOrderid = StringFind(message, "orderid", 0) >= 0 && orderdata.isInt("orderid");
  bool hasType = StringFind(message, "type", 0) >= 0 && orderdata.isInt("type");
  bool hasLots = StringFind(message, "lots", 0) >= 0 && orderdata.isDouble("lots");
  bool hasLotspercent = StringFind(message, "lotspercent", 0) >= 0 && orderdata.isDouble("lotspercent");
  bool hasLotpartial = StringFind(message, "lotspartial", 0) >= 0 && orderdata.isDouble("lotspartial");
  bool hasEntry = StringFind(message, "entry", 0) >= 0 && orderdata.isDouble("entry");
  bool hasSL = StringFind(message, "sl", 0) >= 0 && orderdata.isDouble("sl");
  bool hasTP = StringFind(message, "tp", 0) >= 0 && orderdata.isDouble("tp");
  bool hasComment = StringFind(message, "comment", 0) >= 0 && orderdata.isString("comment");
  
  bool result = false;  
  bool validOpen=hasSymbol&&hasOrderid&&hasType&&hasEntry&&hasLots&&hasLotspercent&&hasSL&&hasTP&&hasComment;
  bool validClose=hasSymbol&&hasOrderid&&hasLots&&hasLotpartial&&hasComment;
  bool validMarket=hasSymbol&&hasType&&hasLots&&hasLotspercent&&hasSL&&hasTP&&hasComment;
  
  if ((type == "open" && !validOpen) || (type == "close" && !validClose) || (type == "market" && !validMarket)) {
      Print("Open Order Json Invalid: ",message);   
      GlobalMessagePlus = "Open Order Json Invalid!";
      return result;
  }

  if (type == "open") {
      string symbol        = orderdata.getString("symbol");
      int    orderid       = orderdata.getInt("orderid");
      int    type          = orderdata.getInt("type");
      double entry         = orderdata.getDouble("entry");
      double lotspercent   = orderdata.getDouble("lotspercent");
      double lots          = orderdata.getDouble("lots");
      double sl            = orderdata.getDouble("sl");
      double tp            = orderdata.getDouble("tp");
      string comment       = orderdata.getString("comment");
      
      symbol = GetOrderSymbolPrefix(symbol);
      if (lots<=0) lots = CalculateLotSizePercent(symbol, MathAbs(entry - sl), lotspercent);
      
      result = MakeOrder(symbol, orderid, -1, type, lots, entry, sl, tp, comment, 1);
   } else if (type == "close") {
      string symbol        = orderdata.getString("symbol");
      int    orderid       = orderdata.getInt("orderid");
      string comment       = orderdata.getString("comment");
      double lots          = orderdata.getDouble("lots");
      double lotspartial   = orderdata.getDouble("lotspartial");
      
      symbol = GetOrderSymbolPrefix(symbol);     

      if (comment != "" || orderid > 0) {
         if (lots > 0 || lotspartial > 0)
            result = MakePositionPartiallyClose(orderid, symbol, comment, lots, lotspartial);
         else
            result = MakeOrderClose(orderid, symbol, comment);
      }
   } else if (type == "market") {
      string symbol        = orderdata.getString("symbol");            
      int    type          = orderdata.getInt("type");
      double lots          = orderdata.getDouble("lots");
      double lotspercent   = orderdata.getDouble("lotspercent");
      double sl            = orderdata.getDouble("sl");
      double tp            = orderdata.getDouble("tp");
      string comment       = orderdata.getString("comment");

      symbol = GetOrderSymbolPrefix(symbol);
      result = MakeOrderMarket(symbol, type, lots, comment, lotspercent, sl);
   }
   delete jv;
   delete orderdata;
   return result;
  }
  
//+------------------------------------------------------------------+
//| Lot size base on percent of Balance                              |
//+------------------------------------------------------------------+
double            CalculateLotSizePercent(string symbol, double SL, double MaxRiskPerTrade, bool isTick = false)
  {
//Calculate the size of the position size
   double LotSize=0;
//We get the value of a tick
   double nTickValue=isTick?SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE):1;

   //double lotMin = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   //double lotMax = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double point = SymbolInfoDouble(symbol,SYMBOL_POINT) * (IsMiniPipBroker?10:1);
//We apply the formula to calculate the position size and assign the value to the variable
   LotSize=(AccountInfoDouble(ACCOUNT_BALANCE)*MaxRiskPerTrade/100)/(SL*nTickValue)*point;
   double lotStep = SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   LotSize=MathRound(LotSize/lotStep)*lotStep;
   LotSize=VerifyOrderLots(symbol, LotSize);
   //LotSize=MathMin(lotMax, LotSize)
   Print("Lotsize: ",LotSize, " - AccountBalance: ", AccountInfoDouble(ACCOUNT_BALANCE), " - point: ", point);   
   
   return LotSize;
  }

//OP_BUY 0
//OP_SELL 1
//OP_BUYLIMIT 2
//OP_SELLLIMIT 3
//OP_BUYSTOP 4
//OP_SELLSTOP 5

//+------------------------------------------------------------------+
//| Make a order by signal message (Market and Pending Order)        |
//+------------------------------------------------------------------+
bool              MakeOrder(const string symbol,
                            const int orderid,
                            const int beforeorderid,
                            const int type,
                            const double lots,
                            const double entry,
                            const double sl,
                            const double tp,
                            const string comment,
                            const int magicnumber)
  {
   if(symbol == "" || orderid == 0)
      return false;

   if(GetOrderSymbolAllowed(symbol) == false)
      return false;

   int    ticketid    = -1;
   bool   orderstatus = false;
   bool   localstatus = false;

   ticketid = FindOrderBySingalComment(symbol, orderid);

   if(ticketid <= 0)
     {
      ticketid = MakeOrderOpen(symbol, type, entry, lots, sl, tp, comment, magicnumber);

      Print("Open:", symbol, ", Type:", type, ", TicketId:", ticketid);
     }

   return (ticketid > 0) ? true : false;
  }

//+------------------------------------------------------------------+
//| Make a market order by signal message from TradingView           |
//+------------------------------------------------------------------+
int               MakeOrderMarket(const string symbol,
                                const int type,
                                const double lots,
                                const string comment,
                                double lots_percent = 0,
                                double sl = 0,
                                double tp = 0)
  {
   int ticketid = -1;

// Allow signal to open the order
// Symbol must not be empty
   if(order_allowopen == false || symbol == "")
      return ticketid;

// Allow Expert Advisor to open the order
   if(TerminalInfoInteger(TERMINAL_DLLS_ALLOWED) == false)
      return ticketid;

// Check if account margin free is less than settings
   if(account_minmarginfree > 0.00 && AccountInfoDouble(ACCOUNT_MARGIN_FREE) < account_minmarginfree)
      return ticketid;

   double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double entry = currentAsk;
   double vlots = VerifyOrderLots(symbol, lots);
   int    vtype = type;
   if (vtype != OP_BUY && vtype != OP_SELL) return ticketid;
   if (vtype == OP_SELL) entry = currentBid;
   
   if (lots_percent > 0 && lots_percent < 5)
      vlots = CalculateLotSizePercent(symbol, MathAbs(entry - sl), lots_percent);
   //double point = SymbolInfoDouble(symbol,SYMBOL_POINT) * (IsMiniPipBroker?10:1);
   //double r_value =(AccountInfoDouble(ACCOUNT_BALANCE)*lots_percent/100);
   //double r_value_min = MinLots/point*MathAbs(entry - sl);
   //comment = comment + " R" + DoubleToString(MathMax(r_value, r_value_min), 2);
// The parameter price must be greater than zero
   MqlTradeResult result={0};
   MqlTradeRequest request={0};
   request.symbol=symbol;
   request.action=TRADE_ACTION_DEAL;
   request.type=vtype;
   request.volume=vlots;
   request.price=entry;
   request.deviation=Slippage;
   request.type_filling=ORDER_FILLING_IOC;
   request.comment=comment;
   if (tp > 0 && sl > 0) {
      request.sl = sl;
      request.tp = tp;
   }
   //request.magic=MAGIC_MANUAL;
   if(!OrderSend(request,result))
      PrintFormat("OrderSend error %d",GetLastError());     // if unable to send the request, output the error code
   PrintFormat("retcode=%u  deal=%I64u  order=%I64u lots=%e symbol=%s",result.retcode,result.deal,result.order,vlots, symbol);
   return result.order;
}
//+------------------------------------------------------------------+
//| Make a order by signal message from TradingView           |
//+------------------------------------------------------------------+
int               MakeOrderOpen(const string symbol,
                                const int type,
                                const double openprice,
                                const double lots,
                                const double sl,
                                const double tp,
                                const string comment,
                                const int magicnumber)
  {
   int ticketid = -1;

// Allow signal to open the order
// Symbol must not be empty
   if(order_allowopen == false || symbol == "")
      return ticketid;

// Allow Expert Advisor to open the order
   if(MQLInfoInteger(MQL_TRADE_ALLOWED) == false)
      return ticketid;

// Check if account margin free is less than settings
   if(account_minmarginfree > 0.00 && AccountInfoDouble(ACCOUNT_MARGIN_FREE) < account_minmarginfree)
      return ticketid;

   double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double spread = MathAbs(currentAsk - currentBid);
   double vprice = openprice;
   double vlots = VerifyOrderLots(symbol, lots);
   int    vtype = type;

// The parameter price must be greater than zero
   if(vprice <= 0.00)
      vprice = SymbolInfoDouble(symbol, SYMBOL_ASK);
   //Correction Order
   if (openprice > 0) {
      if (openprice == sl || openprice == tp) {
         Print("SlopLoss or TargetProfit invalid! ENTRY = ", openprice, "; TP = ", tp, "; SL = ", sl);
         GlobalMessagePlus = "SlopLoss or TargetProfit invalid!";
         return -1;
      }
      if (openprice > sl) { //GO LONG
         if (openprice < currentAsk)
            vtype = OP_BUYLIMIT;
         else if (openprice > currentAsk)
            vtype = OP_BUYSTOP;
         else //openprice == currentAsk
            vtype = OP_BUY;
      }
      if (openprice < sl) { //GO SHORT
         if (openprice < currentBid)
            vtype = OP_SELLSTOP;
         else if (openprice > currentBid)
            vtype = OP_SELLLIMIT;
         else //openprice == currentBid
            vtype = OP_BUY;
      }
   }
   MqlTradeResult result={0};
   MqlTradeRequest request={0};
   request.symbol=symbol;
   request.type=vtype;
   request.volume=vlots;
   request.price=openprice;
   request.sl = sl;
   request.tp = tp;
   request.magic = magicnumber;
   request.deviation=Slippage;
   request.comment=comment;

   switch(vtype)
     {
      case OP_BUY:
         request.action=TRADE_ACTION_DEAL;
         request.price=currentAsk;
         OrderSend(request,result);
         break;

      case OP_SELL:
         request.action=TRADE_ACTION_DEAL;
         request.price=currentBid;
         request.sl = sl + spread;
         request.tp = tp + spread;
         OrderSend(request,result);
         break;

      case OP_BUYLIMIT:
         if(openprice > 0.00) {
            request.action=TRADE_ACTION_PENDING;
            OrderSend(request,result);
         }
         break;

      case OP_BUYSTOP:
         if(openprice > 0.00) {
            request.action=TRADE_ACTION_PENDING;
            OrderSend(request,result);
         }
         break;

      case OP_SELLLIMIT:
         if(openprice > 0.00) {
            request.action=TRADE_ACTION_PENDING;
            request.sl = sl + spread;
            request.tp = tp + spread;
            OrderSend(request,result);
         }
         break;

      case OP_SELLSTOP:
         if(openprice > 0.00) {
            request.action=TRADE_ACTION_PENDING;
            request.sl = sl + spread;
            request.tp = tp + spread;
            OrderSend(request,result);
         }
         break;
     }

   return result.order;
  }

//+------------------------------------------------------------------+
//| Make a order close by signal message                             |
//+------------------------------------------------------------------+
int              MakeOrderClose(const int ticketid,
                                 const string symbol,
                                 const string comment)
  {
//--- declare and initialize the trade request and result of trade request
   MqlTradeRequest request;
   MqlTradeResult  result;
   int total=PositionsTotal(); // number of open positions   
//--- iterate over all open positions
   for(int i=total-1; i>=0; i--)
     {
      //--- parameters of the order
      ulong  position_ticket=PositionGetTicket(i);                                      // ticket of the position
      string position_symbol=PositionGetString(POSITION_SYMBOL);                        // symbol 
      int    digits=(int)SymbolInfoInteger(position_symbol,SYMBOL_DIGITS);              // number of decimal places
      ulong  magic=PositionGetInteger(POSITION_MAGIC);                                  // MagicNumber of the position
      double volume=PositionGetDouble(POSITION_VOLUME);       
      string position_comment=PositionGetString(POSITION_COMMENT);                          // comment of the position
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);    // type of the position
      //--- output information about the position
      PrintFormat("#%I64u %s  %s  %.2f  %s [%I64d]",
                  position_ticket,
                  position_symbol,
                  EnumToString(type),
                  volume,
                  DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),digits),
                  magic);
      //--- if the MagicNumber matches
      if ((comment != "" && comment==position_comment) || ticketid==position_ticket)
        {
         //--- zeroing the request and result values
         ZeroMemory(request);
         ZeroMemory(result);
         //--- setting the operation parameters
         request.action   =TRADE_ACTION_DEAL;        // type of trade operation
         request.position =position_ticket;          // ticket of the position
         request.symbol   =position_symbol;          // symbol 
         request.volume   =volume;                   // volume of the position
         request.deviation=5;                        // allowed deviation from the price
         request.type_filling=ORDER_FILLING_IOC;
         //request.magic    =EXPERT_MAGIC;             // MagicNumber of the position
         //--- set the price and order type depending on the position type
         if(type==POSITION_TYPE_BUY)
           {
            request.price=SymbolInfoDouble(position_symbol,SYMBOL_BID);
            request.type =ORDER_TYPE_SELL;
           }
         else
           {
            request.price=SymbolInfoDouble(position_symbol,SYMBOL_ASK);
            request.type =ORDER_TYPE_BUY;
           }
         //--- output information about the closure
         PrintFormat("Close #%I64d %s %s",position_ticket,position_symbol,EnumToString(type));
         //--- send the request
         if(!OrderSend(request,result))
            PrintFormat("OrderSend error %d",GetLastError());  // if unable to send the request, output the error code
         //--- information about the operation   
         PrintFormat("retcode=%u  deal=%I64u  order=%I64u",result.retcode,result.deal,result.order);
         //---
        }
     }

   total=OrdersTotal(); // total number of placed pending orders
//--- iterate over all placed pending orders
   for(int i=total-1; i>=0; i--)
     {
      ulong  order_ticket=OrderGetTicket(i);                   // order ticket
      string  order_comment=OrderGetString(ORDER_COMMENT);               // comment of the order
      //--- if the MagicNumber matches
      if((comment!=""&&order_comment==comment)||ticketid==order_ticket)
        {
         //--- zeroing the request and result values
         ZeroMemory(request);
         ZeroMemory(result);
         //--- setting the operation parameters     
         request.action=TRADE_ACTION_REMOVE;                   // type of trade operation
         request.order = order_ticket;                         // order ticket
         request.type_filling=ORDER_FILLING_IOC;
         //--- send the request
         if(!OrderSend(request,result))
            PrintFormat("OrderSend error %d",GetLastError());  // if unable to send the request, output the error code
         //--- information about the operation   
         PrintFormat("retcode=%u  deal=%I64u  order=%I64u",result.retcode,result.deal,result.order);
        }
     }
   return result.order;
  
  }

//+------------------------------------------------------------------+
//| Make a partially order close by signal message                   |
//+------------------------------------------------------------------+
int              MakePositionPartiallyClose(const int ticketid,
      const string symbol,
      const string comment,
      const double lots,
      const double percentpartial)
  {
   MqlTradeResult result={0};
   MqlTradeRequest request={0};
   int vid = ticketid;
   double vlots=lots;
//   if (vid <= 0 && comment != "") vid = FindPositionByComment(symbol, comment);
//// Allow signal to close the order
//// The parameter ticketid must be greater than zero
//   if(vid <= 0) {
//      Print("Can't find order from comment"); 
//      GlobalMessagePlus = "Can't find order from comment";
//      return result.order;   
//   }
// Allow Expert Advisor to close the order
   if(order_allowclose == false || MQLInfoInteger(MQL_TRADE_ALLOWED) == false) {
      return result.order;
   }
   int total=PositionsTotal(); // number of open positions   
   bool found = false;
//--- iterate over all open positions
   for(int i=total-1; i>=0; i--)
     {
      //--- parameters of the order
      ulong  position_ticket=PositionGetTicket(i);           
      string position_comment=PositionGetString(POSITION_COMMENT);
      string position_symbol=PositionGetString(POSITION_SYMBOL);
      if (symbol != position_symbol) continue;
      if ((position_ticket >0&&position_ticket==ticketid) || (comment!=""&&comment == position_comment)) 
         {
            //--- zeroing the request and result values
            ZeroMemory(request);
            ZeroMemory(result);
            found = true;
            double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
            //lots calculation
            double vcloselots = PositionGetDouble(POSITION_VOLUME);
            if (vlots <= 0 && percentpartial > 0 && percentpartial <= 100) vlots = vcloselots * percentpartial / 100; //%
            double lotStep = SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
            vlots=MathFloor(vlots/lotStep)*lotStep;            
            vlots      = VerifyOrderLots(symbol, vlots);      
            int type          = PositionGetInteger(POSITION_TYPE);
            
            request.action=TRADE_ACTION_DEAL;
            request.symbol = symbol;
            request.position=position_ticket;
            request.volume=vlots;
            request.deviation=Slippage;
            request.comment=position_comment;
            request.type_filling=ORDER_FILLING_IOC;
            
            switch(type)
              {
               case POSITION_TYPE_BUY:
                  request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
                  request.type=ORDER_TYPE_SELL;
                  break;
               case POSITION_TYPE_SELL:
                  request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
                  request.type=ORDER_TYPE_BUY;
                  break;
              }
              if(!OrderSend(request,result))
                  PrintFormat("OrderSend error %d",GetLastError());  // if unable to send the request, output the error code
               //--- information about the operation   
               PrintFormat("retcode=%u  deal=%I64u  order=%I64u",result.retcode,result.deal,result.order);
               break;
         }
      }
     if (!found) {
         Print("TicketID no exist"); 
         GlobalMessagePlus = "TicketID no exist";
     }
   return result.order;
  }

//+------------------------------------------------------------------+
//| Make a order modify by signal message                            |
//+------------------------------------------------------------------+
int              MakeOrderModify(const int ticketid,
                                  const string symbol,
                                  const double openprice,
                                  const double sl,
                                  const double tp)
  {
   MqlTradeResult result={0};
   MqlTradeRequest request={0};
// Allow signal to modify the order
// The parameter ticketid must be greater than zero
   if(order_allowmodify == false || ticketid <= 0)
      return result.order;

// Allow Expert Advisor to modify the order
   if(MQLInfoInteger(MQL_TRADE_ALLOWED) == false)
      return result.order;
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double spread = MathAbs(ask - bid);
   if(OrderSelect(ticketid) == true)
     {
         int type          = OrderGetInteger(ORDER_TYPE);

         
         request.deviation=Slippage;
         switch(type)
           {
            case OP_BUYLIMIT:
            case OP_BUYSTOP:
               request.order=ticketid;
               request.action=TRADE_ACTION_MODIFY;
               request.sl      =sl;                // Stop Loss of the position
               request.tp      =tp;                // Take Profit of the position
               break;
            case OP_SELLLIMIT:
            case OP_SELLSTOP:
               request.order=ticketid;
               request.action=TRADE_ACTION_MODIFY;
               request.sl      =sl + spread;                // Stop Loss of the position
               request.tp      =tp + spread;                // Take Profit of the position
               break;
            case OP_BUY:
               request.action  =TRADE_ACTION_SLTP; // type of trade operation
               request.position=ticketid;          // ticket of the position
               request.sl      =sl;                // Stop Loss of the position
               request.tp      =tp;                // Take Profit of the position
               break;
            case OP_SELL:
               request.action  =TRADE_ACTION_SLTP; // type of trade operation
               request.position=ticketid;          // ticket of the position
               request.sl      =sl + spread;                // Stop Loss of the position
               request.tp      =tp + spread;                // Take Profit of the position
               break;
           }
         OrderSend(request,result);
     }

   return result.order;
  }

//+------------------------------------------------------------------+
//| Get the order lots is greater than or less than max and min lots |
//+------------------------------------------------------------------+
double            VerifyOrderLots(const string symbol, const double lots)
  {
   double result = lots;

   if(order_percentlots > 0)
     {
      result = lots * (order_percentlots / 100);
     }

   if(order_minlots > 0.00)
      result = (lots <= order_minlots) ? order_minlots : result;

   if(order_maxlots > 0.00)
      result = (lots >= order_maxlots) ? order_maxlots : result;

   if(order_percentlots > 0)
     {
      double s_maxlots = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double s_mixlots = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

      if(result > s_maxlots)
         result = s_maxlots;

      if(result < s_mixlots)
         result = s_mixlots;
     }

   return result;
  }

//+------------------------------------------------------------------+
//| Get the order symbol between A broker and B broker               |
//+------------------------------------------------------------------+
string            GetOrderSymbolPrefix(const string symbol)
  {
   string result = symbol;

   if(symbolprefix_size == 0)
      return result;

   int symbolsize = StringLen(symbol);
   int symbolindex = 0;

   for(symbolindex=0; symbolindex<symbolprefix_size; symbolindex++)
     {
      int prefixsize         = StringLen(local_symbolprefix[symbolindex].s_name);
      string symbolname      = StringSubstr(symbol, 0, symbolsize-prefixsize);
      string tradesymbolname = symbolname + local_symbolprefix[symbolindex].d_name;

      if(symbolname + local_symbolprefix[symbolindex].s_name != symbol)
         continue;

      if(SymbolInfoString(tradesymbolname, SYMBOL_CURRENCY_BASE) != "")
        {
         result = tradesymbolname;

         break;
        }
     }

   return result;
  }

//+------------------------------------------------------------------+
//| Get the symbol allowd on trading                                 |
//+------------------------------------------------------------------+
bool              GetOrderSymbolAllowed(const string symbol)
  {
   bool result = true;

   if(symbolallow_size == 0)
      return result;

// Change result as FALSE when allow list is not empty
   result = false;

   int symbolindex = 0;

   for(symbolindex=0; symbolindex<symbolallow_size; symbolindex++)
     {
      if(local_symbolallow[symbolindex] == "")
         continue;

      if(symbol == local_symbolallow[symbolindex])
        {
         result = true;

         break;
        }
     }

   return result;
  }

//+------------------------------------------------------------------+
//| Find a current order by comment                                  |
//+------------------------------------------------------------------+
int               FindOrderByComment(const string symbol,
      const string comment)
  {
   int ticketid = -1;

   int ordersize  = OrdersTotal();
   int orderindex = 0;

   for(orderindex=0; orderindex<ordersize; orderindex++)
     {
        ulong ticketid = OrderGetTicket(orderindex);
        if (ticketid > 0) 
         {
         //if(OrderSelect(ticketid) == false)
            //continue;
   
            string ordercomment = OrderGetString(ORDER_COMMENT);// OrderComment();
      
            if(ordercomment == "")
               continue;
            // Find a order ticket id from order comment.
            // Order by signal is login|orderid
            if(symbol == OrderGetString(ORDER_SYMBOL)// OrderSymbol()
               && comment == ordercomment)
              {
               ticketid = OrderGetInteger(ORDER_TICKET);// OrderTicket();
      
               if(ticketid > 0)
                  break;
              }
           }
     }

   return ticketid;
  }
//+------------------------------------------------------------------+
//| Find a current position by comment                                  |
//+------------------------------------------------------------------+
int               FindPositionByComment(const string symbol,
      const string comment)
  {
   int ticketid = -1;

   int ordersize  = PositionsTotal();
   int orderindex = 0;

   for(orderindex=0; orderindex<ordersize; orderindex++)
     {
        ulong ticketid = PositionGetTicket(orderindex);
        string ordercomment = PositionGetString(POSITION_COMMENT);// OrderComment();
        if (ticketid > 0 && ordercomment != "" && symbol == PositionGetString(POSITION_SYMBOL) && comment == ordercomment) 
            return ticketid;
     }

   return ticketid;
  }
//+------------------------------------------------------------------+
//| Find a current order by server signal                            |
//+------------------------------------------------------------------+
int               FindOrderBySingalComment(const string symbol,
      const int signal_ticketid)
  {
   int ticketid = -1;

   int ordersize  = OrdersTotal();
   int orderindex = 0;

   for(orderindex=0; orderindex<ordersize; orderindex++)
     {
     ulong ticketid = OrderGetTicket(orderindex);
      if(OrderSelect(ticketid) == false)
         continue;

      string ordercomment = OrderGetString(ORDER_COMMENT);// OrderComment();

      if(ordercomment == "")
         continue;

      string singalorderdata[];
      int    size = StringSplit(ordercomment, '|', singalorderdata);

      if(size != 2)
         continue;

      // Find a order ticket id from order comment.
      // Order by signal is login|orderid
      if(symbol == OrderGetString(ORDER_SYMBOL)// OrderSymbol()
         && signal_ticketid == StringToInteger(singalorderdata[1]))
        {
         ticketid = OrderGetTicket(ORDER_TICKET);// OrderTicket();

         if(ticketid > 0)
            break;
        }
     }

   return ticketid;
  }

//+------------------------------------------------------------------+
//| Find a history order closed by server signal                     |
//+------------------------------------------------------------------+
int               FindClosedOrderByHistoryToComment(const string symbol,
      const int signal_ticketid)
  {
   int ticketid = -1;

   int ordersize  = HistoryOrdersTotal();
   int orderindex = 0;

// Find a history order closed by part-close order
   for(orderindex=0; orderindex<ordersize; orderindex++)
     {
     ulong ticketid = PositionGetTicket(orderindex);
      if(OrderSelect(ticketid) == false)
         continue;

      string ordercomment = OrderGetString(ORDER_COMMENT);// OrderComment();

      if(ordercomment == "")
         continue;

      if(symbol != OrderGetString(ORDER_SYMBOL))// OrderSymbol())
         continue;

      if(signal_ticketid != OrderGetInteger(ORDER_TICKET))// OrderTicket())
         continue;

      // Find a part-close flag in comment column
      if(StringFind(ordercomment, "to #", 0) >= 0)
        {
         if(StringReplace(ordercomment, "to #", "") >= 0)
           {
            ticketid = StringToInteger(ordercomment);

            if(ticketid > 0)
               break;
           }
        }
     }

   return ticketid;
  }

//+------------------------------------------------------------------+
//| Find a part closed order by server signal                        |
//+------------------------------------------------------------------+
int               FindPartClosedOrderByLocal(const string symbol,
      const int signal_ticketid)
  {
   int ticketid = -1;

   int before_orderid = -1;
   int pclosedsize  = ArraySize(local_pclosed);
   int pclosedindex = 0;

   for(pclosedindex=0; pclosedindex<pclosedsize; pclosedindex++)
     {
      if(local_pclosed[pclosedindex].s_orderid == signal_ticketid)
        {
         before_orderid = local_pclosed[pclosedindex].orderid;

         break;
        }
     }

// Find a orderid from history closed by part-close order
   if(before_orderid > 0)
      ticketid = FindClosedOrderByHistoryToComment(symbol, before_orderid);

   return ticketid;
  }

//+------------------------------------------------------------------+
//| Local closed data save                                           |
//+------------------------------------------------------------------+
bool              LocalClosedDataSave(const int s_orderid,
                                      const int sl_beforeorderid,
                                      const int orderid)
  {
   bool result = false;

   int local_pclosedsize = ArraySize(local_pclosed);

   if(ArrayResize(local_pclosed, local_pclosedsize + 1))
     {
      local_pclosed[local_pclosedsize].s_orderid = s_orderid;
      local_pclosed[local_pclosedsize].s_before_orderid = sl_beforeorderid;
      local_pclosed[local_pclosedsize].orderid = orderid;
     }

   return result;
  }

//+------------------------------------------------------------------+
//| Local closed data to memory                                      |
//+------------------------------------------------------------------+
void              LocalClosedDataToMemory()
  {
   int    login    = AccountInfoInteger(ACCOUNT_LOGIN);
   string filename = IntegerToString(login) + "_" + local_pclosedfilename;

   int handle = FileOpen(local_drectoryname + "//" + filename, FILE_READ|FILE_BIN);

   if(handle != INVALID_HANDLE)
     {
      FileReadArray(handle, local_pclosed);
      FileClose(handle);
     }
   else
     {
      Print("Failed to open the closed order file, error ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Local closed data to file                                        |
//+------------------------------------------------------------------+
void              LocalClosedDataToFile()
  {
   int    login    = AccountInfoInteger(ACCOUNT_LOGIN);
   string filename = IntegerToString(login) + "_" + local_pclosedfilename;

   int handle = FileOpen(local_drectoryname + "//" + filename, FILE_WRITE|FILE_BIN);

   if(handle != INVALID_HANDLE)
     {
      int local_pclosedsize = ArraySize(local_pclosed);

      FileSeek(handle, 0, SEEK_END);
      FileWriteArray(handle, local_pclosed, 0, local_pclosedsize);
      FileClose(handle);
     }
   else
     {
      Print("Failed to open the closed order file, error ", GetLastError());
     }
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
