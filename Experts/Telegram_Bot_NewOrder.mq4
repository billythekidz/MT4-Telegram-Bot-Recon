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
input string            InpToken="1037718376:AAGCaiUwO8682dDdSEYxcKl0SQegTQMr3Cg"; //Trading Bot Telegram Token
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
int init()
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
void deinit(const int reason)
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
//|   JSON PROCESS                                                  |
//+------------------------------------------------------------------+
void TestJson()
  {
   string s = "{ \"firstName\": \"John\", \"lastName\": \"Smith\", \"age\": 25, "+
              "\"address\": { \"streetAddress\": \"21 2nd Street\", \"city\": \"New York\", \"state\": \"NY\", \"postalCode\": \"10021\" },"+
              " \"phoneNumber\": [ { \"type\": \"home\", \"number\": \"212 555-1234\" }, { \"type\": \"fax\", \"number\": \"646 555-4567\" } ],"+
              " \"gender\":{ \"type\":\"male\" }  }";

   JSONValue *jv = parser.parse(s);

   if(jv == NULL)
     {
      Print("error:"+(string)parser.getErrorCode()+parser.getErrorMessage());
     }
   else
     {


      Print("PARSED:"+jv.toString());

      if(jv.isObject())    // check root value is an object. (it can be an array)
        {

         JSONObject *jo = jv;

         // Direct access - will throw null pointer if wrong getter used.
         Print("firstName:" + jo.getString("firstName"));
         Print("city:" + jo.getObject("address").getString("city"));
         Print("phone:" + jo.getArray("phoneNumber").getObject(0).getString("number"));

         // Safe access in case JSON data is missing or different.
         if(jo.getString("firstName",s))
            Print("firstName = "+s);

         // Loop over object keys
         JSONIterator *it = new JSONIterator(jo);
         for(; it.hasNext() ; it.next())
           {
            Print("loop:"+it.key()+" = "+it.val().toString());
           }
         delete it;
        }
     }
   delete jv;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool TestJson2()
  {
   string s = "{ \"op\": \"OPEN\", \"symbol\": \"EURUSD\", \"orderid\": 11213, "+
              "\"beforeorderid\": 11212,"+
              " \"type\": 0,"+
              " \"openprice\": 1.11000,"+
              " \"closeprice\": 1.11000,"+
              " \"lots\": 0.01000,"+
              " \"lotspercent\": 1.5,"+
              " \"sl\": 1.10000,"+
              " \"tp\": 1.12000}";

   JSONValue *jv = parser.parse(s);

   if(jv == NULL)
     {
      Print("error:"+(string)parser.getErrorCode()+parser.getErrorMessage());
      return false;
     }
   else
     {


      Print("PARSED:"+jv.toString());

      if(jv.isObject())    // check root value is an object. (it can be an array)
        {

         JSONObject *jo = jv;

         // Direct access - will throw null pointer if wrong getter used.
         Print("op:" + jo.getString("op"));
         Print("symbol:" + jo.getString("symbol"));
         Print("orderid:" + jo.getInt("orderid"));
         Print("beforeorderid:" + jo.getInt("beforeorderid"));
         Print("type:" + jo.getInt("type"));
         Print("openprice:" + jo.getDouble("openprice"));
         Print("closeprice:" + jo.getDouble("closeprice"));
         Print("lots:" + jo.getDouble("lots"));
         Print("lotspercent:" + jo.getDouble("lotspercent"));
         Print("sl:" + jo.getDouble("sl"));
         Print("tp:" + jo.getDouble("tp"));
         // Safe access in case JSON data is missing or different.
         if(jo.getString("firstName",s))
            Print("firstName = "+s);

         // Loop over object keys
         JSONIterator *it = new JSONIterator(jo);
         for(; it.hasNext() ; it.next())
           {
            Print("loop:"+it.key()+" = "+it.val().toString());
           }
         delete it;
         return true;
        }
      return false;
     }
   delete jv;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//--- Inputs
input string OrderSegment            = "----------------------------";
input bool   IsMiniPipBroker         = false;
input double MinLots                 = 0.01;                    // Limit the minimum lots (Default is 0.00)
input double MaxLots                 = 1;                    // Limit the maximum lots (Default is 0.00)
input double PercentLots             = 100;                     // Lots Percent from Signal (Default is 100)
input int    Slippage                = 3;
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
   JSONObject *obj = new JSONObject();
   
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

   if(IsDllsAllowed() == false)
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
string              MessageReceive(string message, string type)
  {
// Load closed order to memory
   LocalClosedDataToMemory();
   
 // Hard code for test only
//    message = "{ \"op\": \"OPEN\", \"symbol\": \"EURUSD\", \"orderid\": 11213, "+
//"\"beforeorderid\": 11212,"+
//" \"type\": 0,"+
//" \"lotspercent\": 1.5,"+
//" \"entry\": 1.11000,"+
//" \"sl\": 1.10000,"+
//" \"tp\": 1.12000,"+
//" \"comment\": \"TREND RIDER 1.5% 2R 12P 15M\"," +
//" \"magic\": 1560240"+
//"}" ;

   if(type == "open" && message != "" && AccountEquity() > 0.00)
     {
         bool checkValid = ParseMessage(message);
         if(checkValid) {
            bool result = ParseOrderFromSingal(message, type);
            if (result) return "ORDER SUCCESSFUL!";
            else {
               int check=GetLastError();
               if(check!=ERR_NO_ERROR) return ("ORDER FAILED: " + ErrorDescription(check));
               return "ORDER FAILED: CAN'T DETECT REASON";
            }
         }
     }
     if(type == "close" && message != "")
     {
         bool result = ParseOrderFromSingal(message, type);
         if (result) return "ORDER SUCCESSFUL!";
         else {
            int check=GetLastError();
            if(check!=ERR_NO_ERROR) return ("ORDER FAILED: " + ErrorDescription(check));
            return "ORDER FAILED: CAN'T DETECT REASON";
         }
     }
     if(type == "market" && message != "" && AccountEquity() > 0.00)
     {
         bool result = ParseOrderFromSingal(message, type);
         if (result) return "ORDER SUCCESSFUL!";
         else {
            int check=GetLastError();
            if(check!=ERR_NO_ERROR) return ("ORDER FAILED: " + ErrorDescription(check));
            return "ORDER FAILED: CAN'T DETECT REASON";
         }
     }
     return "WRONG JSON"; 
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

         JSONObject *jo = jv;

         // Direct access - will throw null pointer if wrong getter used.
         Print("op:" + jo.getString("op"));
         Print("symbol:" + jo.getString("symbol"));
         Print("orderid:" + jo.getInt("orderid"));
         Print("type:" + jo.getInt("type"));
         //Print("lots:" + jo.getDouble("lots"));
         Print("lotspercent:" + jo.getDouble("lotspercent"));
         Print("entry:" + jo.getDouble("entry"));
         Print("sl:" + jo.getDouble("sl"));
         Print("tp:" + jo.getDouble("tp"));
         Print("comment:" + jo.getString("comment"));
         Print("magic:" + jo.getInt("magic"));
         // Loop over object keys
         //JSONIterator *it = new JSONIterator(jo);
         //for(; it.hasNext() ; it.next())
         //  {
         //   Print("loop:"+it.key()+" = "+it.val().toString());
         //  }
         delete jo;
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
bool              ParseOrderFromSingal(const string message, string type)
  {
  JSONValue *jv = parser.parse(message);
  JSONObject*orderdata = jv;
  
  if (type == "open") {
   // Order data from signal
      string op            = orderdata.getString("op"); //OPEN | CLOSED | PCLOSED | MODIFY
      string symbol        = orderdata.getString("symbol");
   //int    orderid       = StrToInteger(orderdata[2]);
      int    orderid       = orderdata.getInt("orderid");
      int    beforeorderid = -1;//orderdata.getInt("beforeorderid");
      int    type          = orderdata.getInt("type");
      double entry         = orderdata.getDouble("entry");
      double lotspercent   = orderdata.getDouble("lotspercent");
      //double lots          = orderdata.getDouble("lots");
      double sl            = orderdata.getDouble("sl");
      double tp            = orderdata.getDouble("tp");
      string comment       = orderdata.getString("comment");
      int magicnumber      = orderdata.getInt("magic");
      symbol = GetOrderSymbolPrefix(symbol);
   
      double lots = CalculateLotSize(symbol, MathAbs(entry - sl), lotspercent);
      
      double point = MarketInfo(symbol,MODE_POINT) * (IsMiniPipBroker?10:1);
      double r_value =(AccountBalance()*lotspercent/100);
      double r_value_min = MinLots/point*MathAbs(entry - sl);
      comment = comment + " R" + DoubleToString(MathMax(r_value, r_value_min), 2);
      
      return MakeOrder(op, symbol, orderid, beforeorderid, type, lots, entry, sl, tp, comment, magicnumber);
   } else if (type == "close") {
      string symbol        = orderdata.getString("symbol");
      int    orderid       = orderdata.getInt("orderid");
      string typeTF          = orderdata.getString("typeTF");
      double lots          = orderdata.getDouble("lots");
      symbol = GetOrderSymbolPrefix(symbol);

      if (lots > 0)
         return MakeOrderPartiallyClose(orderid, symbol, typeTF, lots);
      else
         return MakeOrderClose(orderid, symbol, typeTF);
   } else if (type == "market") {
      string symbol        = orderdata.getString("symbol");
      string typeTF        = orderdata.getString("typeTF");
      double lots          = orderdata.getDouble("lots");
      string orderType     = orderdata.getString("orderType");
      double lotspercent   = orderdata.getDouble("lots_percent");
      double sl            = orderdata.getDouble("stop_loss");
      int orderTypeInt     = -1;
      if (orderType == "long") orderTypeInt = 0;
      else if (orderType == "short") orderTypeInt = 1;
      else return false;
      
      symbol = GetOrderSymbolPrefix(symbol);

      return MakeOrderMarket(symbol, orderTypeInt, lots, typeTF, lotspercent, sl);
   }
   return false;
  }
  
//+------------------------------------------------------------------+
//| Lot size base on percent of Balance                              |
//+------------------------------------------------------------------+
double            CalculateLotSize(string symbol, double SL, double MaxRiskPerTrade, bool isTick = false)
  {
//Calculate the size of the position size
   double LotSize=0;
//We get the value of a tick
   double nTickValue=isTick?MarketInfo(symbol,MODE_TICKVALUE):1;
   double lotStep = MarketInfo(symbol,MODE_LOTSTEP);
   double point = MarketInfo(symbol,MODE_POINT) * (IsMiniPipBroker?10:1);
//We apply the formula to calculate the position size and assign the value to the variable
   LotSize=(AccountBalance()*MaxRiskPerTrade/100)/(SL*nTickValue)*point;
   LotSize=MathRound(LotSize/lotStep)*lotStep;
   Print("Lotsize: ",LotSize, " - AccountBalance: ", AccountBalance(), " - point: ", point);
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
bool              MakeOrder(const string op,
                            const string symbol,
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

   if(op == "OPEN")
     {
      ticketid = FindOrderBySingalComment(symbol, orderid);

      if(ticketid <= 0)
        {
         ticketid = MakeOrderOpen(symbol, type, entry, lots, sl, tp, comment, magicnumber);

         Print("Open:", symbol, ", Type:", type, ", TicketId:", ticketid);
        }
     }
//   else
//      if(op == "CLOSED")
//        {
//         ticketid = FindOrderBySingalComment(symbol, orderid);
//
//         if(ticketid <= 0)
//           {
//            ticketid = FindPartClosedOrderByLocal(symbol, orderid);
//           }
//
//         if(ticketid > 0)
//           {
//            orderstatus = MakeOrderClose(ticketid, symbol, type, entry, lots, sl, tp);
//
//            Print("Closed:", symbol, ", Type:", type);
//           }
//        }
//      else
////         if(op == "PCLOSED")
////           {
////            ticketid = FindOrderBySingalComment(symbol, beforeorderid);
////
////            if(ticketid > 0)
////              {
////               //string localmessage = StringFormat("%d|%d-%d|%d", login, orderid, beforeorderid, ticketid);
////               localstatus = LocalClosedDataSave(orderid, beforeorderid, ticketid);
////               orderstatus = MakeOrderPartiallyClose(ticketid, symbol, type, entry, lots, sl, tp);
////
////               Print("Partially Closed:", symbol, ", Type:", type);
////              }
////           }
////         else
//            if(op == "MODIFY")
//              {
//               ticketid = FindOrderBySingalComment(symbol, orderid);
//
//               if(ticketid <= 0)
//                 {
//                  ticketid = FindPartClosedOrderByLocal(symbol, orderid);
//                 }
//
//               if(ticketid > 0)
//                 {
//                  orderstatus = MakeOrderModify(ticketid, symbol, entry, sl, tp);
//
//                  Print("Modify:", symbol, ", Type:", type);
//                 }
//              }

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
                                double sl = 0)
  {
   int ticketid = -1;

// Allow signal to open the order
// Symbol must not be empty
   if(order_allowopen == false || symbol == "")
      return ticketid;

// Allow Expert Advisor to open the order
   if(IsTradeAllowed() == false)
      return ticketid;

// Check if account margin free is less than settings
   if(account_minmarginfree > 0.00 && AccountInfoDouble(ACCOUNT_MARGIN_FREE) < account_minmarginfree)
      return ticketid;

   double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double entry = currentAsk;
   double vlots = GetOrderLots(symbol, lots);
   int    vtype = type;
   if (vtype != OP_BUY && vtype != OP_SELL) return ticketid;
   if (vtype == OP_SELL) entry = currentBid;
   
   if (lots_percent > 0 && lots_percent < 5)
      vlots = CalculateLotSize(symbol, MathAbs(entry - sl), lots_percent);
   //double point = MarketInfo(symbol,MODE_POINT) * (IsMiniPipBroker?10:1);
   //double r_value =(AccountBalance()*lots_percent/100);
   //double r_value_min = MinLots/point*MathAbs(entry - sl);
   //comment = comment + " R" + DoubleToString(MathMax(r_value, r_value_min), 2);
// The parameter price must be greater than zero
   ticketid = OrderSend(symbol, vtype, vlots, entry, 10, 0, 0, comment, 0, 0, clrYellow);
//   switch(vtype)
//     {
//      case OP_BUY:
//         ticketid = OrderSend(symbol, OP_BUY, vlots, entry, 10, 0, 0, comment, 0, 0, clrYellow);
//         break;
//
//      case OP_SELL:
//         ticketid = OrderSend(symbol, OP_SELL, vlots, entry, 10, 0, 0, comment, 0, 0, clrYellow);
//         break;
//     }

   return ticketid;
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
   if(IsTradeAllowed() == false)
      return ticketid;

// Check if account margin free is less than settings
   if(account_minmarginfree > 0.00 && AccountInfoDouble(ACCOUNT_MARGIN_FREE) < account_minmarginfree)
      return ticketid;

   double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double vprice = openprice;
   double vlots = GetOrderLots(symbol, lots);
   int    vtype = type;

// The parameter price must be greater than zero
   if(vprice <= 0.00)
      vprice = SymbolInfoDouble(symbol, SYMBOL_ASK);
   //Correction Order
   if (openprice > 0) {
      if (openprice == sl || openprice == tp) {
         Print("SlopLoss or TargetProfit invalid! ENTRY = ", openprice, "; TP = ", tp, "; SL = ", sl);
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
   
   switch(vtype)
     {
      case OP_BUY:
         ticketid = OrderSend(symbol, OP_BUY, vlots, currentAsk, order_slippage, sl, tp, comment, magicnumber, 0, clrYellow);
         break;

      case OP_SELL:
         ticketid = OrderSend(symbol, OP_SELL, vlots, currentBid, order_slippage, sl, tp, comment, magicnumber, 0, clrYellow);
         break;

      case OP_BUYLIMIT:
         if(openprice > 0.00)
            ticketid = OrderSend(symbol, OP_BUYLIMIT, vlots, openprice, order_slippage, sl, tp, comment, magicnumber, 0, clrYellow);
         break;

      case OP_BUYSTOP:
         if(openprice > 0.00)
            ticketid = OrderSend(symbol, OP_BUYSTOP, vlots, openprice, order_slippage, sl, tp, comment, magicnumber, 0, clrYellow);
         break;

      case OP_SELLLIMIT:
         if(openprice > 0.00)
            ticketid = OrderSend(symbol, OP_SELLLIMIT, vlots, openprice, order_slippage, sl, tp, comment, magicnumber, 0, clrYellow);
         break;

      case OP_SELLSTOP:
         if(openprice > 0.00)
            ticketid = OrderSend(symbol, OP_SELLSTOP, vlots, openprice, order_slippage, sl, tp, comment, magicnumber, 0, clrYellow);
         break;
     }

   return ticketid;
  }
//+------------------------------------------------------------------+
//| Make a order close by signal message                             |
//+------------------------------------------------------------------+
bool              MakeOrderClose(const int ticketid,
                                 const string symbol,
                                 const string typeTF)
  {
   bool result = false;
   int vid = ticketid;
   if (vid <= 0) vid = FindOrderByComment(symbol, typeTF);
// Allow signal to close the order
// The parameter ticketid must be greater than zero
   if(order_allowclose == false || vid <= 0)
      return result;

// Allow Expert Advisor to close the order
   if(IsTradeAllowed() == false)
      return result;

   if(OrderSelect(vid, SELECT_BY_TICKET, MODE_TRADES) == true)
     {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      int type = OrderType();
      
      switch(type)
        {
         case OP_BUYLIMIT:
         case OP_BUYSTOP:
         case OP_SELLLIMIT:
         case OP_SELLSTOP:
            result = OrderDelete(vid);
            break;
         case OP_BUY:
            result = OrderClose(vid, OrderLots(), bid, 100, clrYellow);
            break;
         case OP_SELL:
            result = OrderClose(vid, OrderLots(), ask, 100, clrYellow);
            break;
        }
     }

   return result;
  }

//+------------------------------------------------------------------+
//| Make a partially order close by signal message                   |
//+------------------------------------------------------------------+
bool              MakeOrderPartiallyClose(const int ticketid,
      const string symbol,
      const string typeTF,
      const double lots)
  {
   bool result = false;
   int vid = ticketid;
   if (vid <= 0) vid = FindOrderByComment(symbol, typeTF);
// Allow signal to close the order
// The parameter ticketid must be greater than zero
   if(order_allowclose == false || vid <= 0)
      return result;

// Allow Expert Advisor to close the order
   if(IsTradeAllowed() == false)
      return result;
   if(OrderSelect(vid, SELECT_BY_TICKET, MODE_TRADES) == true)
     {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double vlots      = GetOrderLots(symbol, lots);
      double vcloselots = OrderLots();
      int type          = OrderType();
      
      //if(vcloselots - vlots > 0)
      //  {
      //   vlots = vcloselots - vlots;
      //  }

      switch(type)
        {
         case OP_BUYLIMIT:
         case OP_BUYSTOP:
         case OP_SELLLIMIT:
         case OP_SELLSTOP:
            break;

         case OP_BUY:
            result = OrderClose(vid, vlots, bid, 100, clrYellow);
            break;
         case OP_SELL:
            result = OrderClose(vid, vlots, ask, 100, clrYellow);
            break;
        }
     }
   return result;
  }

//+------------------------------------------------------------------+
//| Make a order modify by signal message                            |
//+------------------------------------------------------------------+
bool              MakeOrderModify(const int ticketid,
                                  const string symbol,
                                  const double openprice,
                                  const double sl,
                                  const double tp)
  {
   bool result = false;

// Allow signal to modify the order
// The parameter ticketid must be greater than zero
   if(order_allowmodify == false || ticketid <= 0)
      return result;

// Allow Expert Advisor to modify the order
   if(IsTradeAllowed() == false)
      return result;

   if(OrderSelect(ticketid, SELECT_BY_TICKET, MODE_TRADES) == true)
     {
      result = OrderModify(ticketid, openprice, sl, tp, 0, clrYellow);
     }

   return result;
  }

//+------------------------------------------------------------------+
//| Get the order lots is greater than or less than max and min lots |
//+------------------------------------------------------------------+
double            GetOrderLots(const string symbol, const double lots)
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
      double s_maxlots = MarketInfo(symbol, MODE_MAXLOT);
      double s_mixlots = MarketInfo(symbol, MODE_MINLOT);

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
      if(OrderSelect(orderindex, SELECT_BY_POS, MODE_TRADES) == false)
         continue;

      string ordercomment = OrderComment();

      if(ordercomment == "")
         continue;
      // Find a order ticket id from order comment.
      // Order by signal is login|orderid
      if(symbol == OrderSymbol()
         && comment == ordercomment)
        {
         ticketid = OrderTicket();

         if(ticketid > 0)
            break;
        }
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
      if(OrderSelect(orderindex, SELECT_BY_POS, MODE_TRADES) == false)
         continue;

      string ordercomment = OrderComment();

      if(ordercomment == "")
         continue;

      string singalorderdata[];
      int    size = StringSplit(ordercomment, '|', singalorderdata);

      if(size != 2)
         continue;

      // Find a order ticket id from order comment.
      // Order by signal is login|orderid
      if(symbol == OrderSymbol()
         && signal_ticketid == StrToInteger(singalorderdata[1]))
        {
         ticketid = OrderTicket();

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

   int ordersize  = OrdersHistoryTotal();
   int orderindex = 0;

// Find a history order closed by part-close order
   for(orderindex=0; orderindex<ordersize; orderindex++)
     {
      if(OrderSelect(orderindex, SELECT_BY_POS, MODE_HISTORY) == false)
         continue;

      string ordercomment = OrderComment();

      if(ordercomment == "")
         continue;

      if(symbol != OrderSymbol())
         continue;

      if(signal_ticketid != OrderTicket())
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
