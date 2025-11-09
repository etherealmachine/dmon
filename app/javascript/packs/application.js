// This file is used by Shakapacker
import '@hotwired/turbo-rails';
import '../controllers';
import '../channels';

import ReactOnRails from 'react-on-rails';
import Toast from '../bundles/Toast/components/Toast';

ReactOnRails.register({
  Toast,
});
