// Configuration for WizGym Admin Dashboard
window.WIZGYM_CONFIG = {
  cognito: {
    region: 'us-east-1',
    userPoolId: 'us-east-1_VSd5foNdB',
    clientId: '1ta05vq4df4in9bnuot076fkct',
    domain: 'wizgym-admin',
  },
  api: {
    baseUrl: 'https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1',
  },
  features: {
    enableDevMode: window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1',
  },
};
