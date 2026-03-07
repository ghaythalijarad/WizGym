// Configuration for WizGym Admin Dashboard
// Update these values for your environment

window.WIZGYM_CONFIG = {
  // Cognito Configuration
  cognito: {
    region: 'eu-north-1',
    userPoolId: 'eu-north-1_XXXXXXXXX', // Replace with your User Pool ID
    clientId: 'XXXXXXXXXXXXXXXXXXXXXXXXXX', // Replace with your App Client ID
    domain: 'wizgym-admin', // Your Cognito domain prefix
  },

  // API Configuration
  api: {
    // Always point to the live AWS Lambda endpoint
    baseUrl: 'https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1',
  },

  // Feature flags
  features: {
    enableDevMode: window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1',
  },
};
