package services
{
	import com.distriqt.extension.dialog.Dialog;
	import com.distriqt.extension.dialog.DialogView;
	import com.distriqt.extension.dialog.builders.AlertBuilder;
	import com.distriqt.extension.dialog.events.DialogViewEvent;
	import com.distriqt.extension.dialog.objects.DialogAction;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.IEventDispatcher;
	import flash.net.URLLoader;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	import flash.net.navigateToURL;
	
	import Utilities.Trace;
	
	import databaseclasses.CommonSettings;
	
	import events.IosXdripReaderEvent;
	import events.SettingsServiceEvent;
	
	import model.ModelLocator;
	
	[ResourceBundle('updateservice')]
	
	public class UpdateService extends EventDispatcher
	{
		//Instance
		private static var _instance:UpdateService = new UpdateService();
		
		//Variables 
		private static var updateURL:String = "";
		private static var latestAppVersion:String = "";
		
		//Constants
		private static const IGNORE_UPDATE_BUTTON:int = 0;
		private static const GO_TO_GITHUB_BUTTON:int = 1;
		private static const REMIND_LATER_BUTTON:int = 2;
		
		public function UpdateService(target:IEventDispatcher=null)
		{
			if (_instance != null) {
				throw new Error("UpdateService class constructor can not be used");	
			}
		}
		
		//Start Engine
		public static function init():void
		{
			//Setup Event Listeners
			createEventListeners();
			
			//Check App Update
			if(canDoUpdate())
				getUpdate();
		}
		
		//Getters/Setters
		public static function get instance():UpdateService {
			return _instance;
		}
		
		//Functionality Functions
		private static function createEventListeners():void
		{
			//Register event listener for app in foreground
			iosxdripreader.instance.addEventListener(IosXdripReaderEvent.APP_IN_FOREGROUND, onApplicationActivated);
			
			//Register event listener for changed settings
			CommonSettings.instance.addEventListener(SettingsServiceEvent.SETTING_CHANGED, onSettingsChanged);
		}
		
		private static function getUpdate():void
		{
			//Create and configure loader and url request
			var request:URLRequest = new URLRequest(CommonSettings.GITHUB_REPO_API_URL);
			request.method = URLRequestMethod.GET;
			var loader:URLLoader = new URLLoader(); 
			loader.dataFormat = URLLoaderDataFormat.TEXT;
			
			//Make connection and define listener
			loader.addEventListener(Event.COMPLETE, onLoadSuccess);
			try 
			{
				loader.load(request);
			}
			catch (error:Error) 
			{
				trace("Unable to load GitHub repo API: " + error);
			}
		}
		
		//Utility functions
		private static function checkDaysBetweenLastUpdateCheck(previousUpdateStamp:Number, currentStamp:Number):Number
		{
			var oneDay:Number = 1000 * 60 * 60 * 24;
			var differenceMilliseconds:Number = Math.abs(previousUpdateStamp - currentStamp);
			var daysAgo:Number =  Math.round(differenceMilliseconds/oneDay);
			
			return daysAgo;
		}
		
		private static function canDoUpdate():Boolean
		{
			/**
			 * Uncomment next line and comment the other one in production environment. 
			 * We are hardcoding a timestamp of more than 1 day ago for testing purposes otherwise the update popup wont fire 
			 */
			var lastUpdateCheckStamp:Number = 1511014007853;
			//var lastUpdateCheckStamp:Number = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_APP_UPDATE_LAST_UPDATE_CHECK) as Number;
			var currentDate:Date = new Date();
			var currentTime:String = (new Date()).toLocaleTimeString();
			var currentTimeStamp:Number = currentDate.valueOf();
			var daysSinceLastUpdateCheck:Number = checkDaysBetweenLastUpdateCheck(lastUpdateCheckStamp, currentTimeStamp);
			
			trace("currentTime: " + currentTime);
			trace("currentTimeStamp: " + currentTimeStamp);
			trace("time between last update: " + daysSinceLastUpdateCheck);
			
			//If it has been more than 1 day since the last check for updates or it's the first time the app checks for updates and app updates are enebled in the settings
			if((daysSinceLastUpdateCheck > 1 || CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_APP_UPDATE_LAST_UPDATE_CHECK) == "") && CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_APP_UPDATE_NOTIFICATIONS_ON) == "true")
			{
				trace("App can check for new updates");
				return true;
			}
			
			return false;
		}
		
		private static function myTrace(log:String):void 
		{
			Trace.myTrace("TextToSpeech.as", log);
		}
		
		//Event Listeners
		protected static function onLoadSuccess(event:Event):void
		{
			//Parse response
			var loader:URLLoader = URLLoader(event.target);
			var data:Object = JSON.parse(loader.data as String);
			
			//Handle App Version
			/**
			* Uncomment next line and comment the other one in production environment. 
			* We are hardcoding a lower app version for testing purposes otherwise the update popup wont fire 
			*/
			//var currentAppVersion:String = LocalSettings.getLocalSetting(LocalSettings.LOCAL_SETTING_APPLICATION_VERSION);
			var currentAppVersion:String = "0.5";
			latestAppVersion = data.tag_name;
			var updateAvailable:Boolean = ModelLocator.versionAIsSmallerThanB(currentAppVersion, latestAppVersion);
			
			//Handle User Update
			if(updateAvailable && latestAppVersion != CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_APP_UPDATE_IGNORE_UPDATE))
			{
				//We are here because the lastest GitHub version is higher than the one installed and the user hasn't chosen to ignore this new version
				//Check if assets are available for download
				var assets:Array = data.assets as Array;
				if(assets.length > 0)
				{
					//Assets are available
					//Define variables
					//var userGroup:int = int("2");
					var userGroup:String = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_APP_UPDATE_USER_GROUP);
					var userUpdateAvailable:Boolean = false;
					
					//Check if there is an update available for the current user's group
					for(var i:int = 0; i < (data.assets as Array).length; i++)
					{
						//Get asset name and type
						var fileName:String = (data.assets as Array)[i].name;
						var fileType:String = (data.assets as Array)[i].content_type;
						
						if (fileType == "application/x-itunes-ipa")
						{
							//Asset is an ipa, let's check what group it belongs
							if(fileName.indexOf("group") >= 0)
							{
								//Get group
								var firstIndex:int = fileName.indexOf("group") + 5;
								var lastIndex:int = fileName.indexOf(".ipa");
								var ipaGroup:String = fileName.slice(firstIndex, lastIndex);
								
								//Does the ipa group match the user group?
								if(userGroup == ipaGroup)
								{
									userUpdateAvailable = true;
									updateURL = data.html_url;
									break;
								}
							}
							else
							{
								//No group associated. This is the main ipa
								if(userGroup == "0" || userGroup == "")
								{
									//The user has no group associated so and update is available
									userUpdateAvailable = true;
									updateURL = data.html_url;
									break;
								}
							}
						}
					}
					
					//If there's an update available to the user, display a notification
					if(userUpdateAvailable)
					{
						//Warn User
						var title:String = ModelLocator.resourceManagerInstance.getString('updateservice', "update_dialog_title");
						var message:String = ModelLocator.resourceManagerInstance.getString('updateservice', "update_dialog_preversion_message") + " " + latestAppVersion + " " + ModelLocator.resourceManagerInstance.getString('updateservice', "update_dialog_postversion_message") + "."; 
						var ignore:String = ModelLocator.resourceManagerInstance.getString('updateservice', "update_dialog_ignore_update");
						var goToGitHub:String = ModelLocator.resourceManagerInstance.getString('updateservice', "update_dialog_goto_github");
						var remind:String = ModelLocator.resourceManagerInstance.getString('updateservice', "update_dialog_remind_later");
						var alert:DialogView = Dialog.service.create(
							new AlertBuilder()
							.setTitle(title)
							.setMessage(message)
							.addOption(ignore, DialogAction.STYLE_POSITIVE, 0)
							.addOption(goToGitHub, DialogAction.STYLE_POSITIVE, 1)
							.addOption(remind, DialogAction.STYLE_POSITIVE, 2)
							.build()
						);
						alert.addEventListener(DialogViewEvent.CLOSED, onDialogClosed);
						DialogService.addDialog(alert);
					}
					else
					{
						//App update is available but no ipa for user's group is ready for download
						updateURL = "";
					}
				}
			}
		}
		
		private static function onDialogClosed(event:DialogViewEvent):void 
		{
			var selectedOption:int = int(event.index);
			if (selectedOption == IGNORE_UPDATE_BUTTON)
			{
				//Add ignored version to database settings
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_APP_UPDATE_IGNORE_UPDATE, latestAppVersion as String);
				
				//Update last check time in database
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_APP_UPDATE_LAST_UPDATE_CHECK, currentTimeStamp as String);
			}
			else if (selectedOption == GO_TO_GITHUB_BUTTON)
			{
				//Go to github release page
				if (updateURL != "")
				{
					navigateToURL(new URLRequest(updateURL));
					updateURL = "";
				}
			}
			else if (selectedOption == REMIND_LATER_BUTTON)
			{
				//User wants to be reminded later (next day)
				var currentDate:Date = new Date();
				var currentTimeStamp:Number = currentDate.valueOf();
				
				//Update last check time in database
				CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_APP_UPDATE_LAST_UPDATE_CHECK, currentTimeStamp as String);
			}
		}
		
		//Event fired when app settings are changed
		private static function onSettingsChanged(event:SettingsServiceEvent):void 
		{
			//Check if an update check can be made
			if (event.data == CommonSettings.COMMON_SETTING_APP_UPDATE_NOTIFICATIONS_ON) 
			{
				myTrace("Settings changed! App update checker is now " + CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_APP_UPDATE_NOTIFICATIONS_ON));
				
				//Let's see if we can make an update
				if(canDoUpdate())
					getUpdate();
			}
		}
		
		protected static function onApplicationActivated(event:Event = null):void
		{
			//App is in foreground. Let's see if we can make an update
			if(canDoUpdate())
				getUpdate();
		}
	}
}