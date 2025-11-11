// This file is used by Shakapacker
import '../channels';

import ReactOnRails from 'react-on-rails';
import Toast from '../bundles/Toast/components/Toast';
import Sidebar from '../bundles/Sidebar';
import GameNotes from '../bundles/GameNotes';
import GamePage from '../bundles/GamePage';

ReactOnRails.register({
  Toast,
  Sidebar,
  GameNotes,
  GamePage,
});
