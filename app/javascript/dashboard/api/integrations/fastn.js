/* global axios */
import ApiClient from '../ApiClient';

class FastnAPI extends ApiClient {
  constructor() {
    super('integrations/fastn', { accountScoped: true });
  }

  createEmbedSession() {
    return axios.post(`${this.url}/embed_session`);
  }
}

export default new FastnAPI();
